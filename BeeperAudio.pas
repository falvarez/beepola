unit BeeperAudio;

// CoreAudio (AudioQueue) output for the beeper emulation on macOS.
// The emulator writes one 882-sample frame per 50 Hz interrupt; when the
// ring buffer is full AudioWriteFrame blocks, so audio paces the emulation.

{$mode delphi}
{$packrecords c}
{$linkframework AudioToolbox}

interface

const
  AUDIO_SAMPLE_RATE = 44100;
  AUDIO_FRAME_SAMPLES = 882;  // one 50 Hz frame

function AudioInit: Boolean;
procedure AudioDone;
// Buf holds Count unsigned 8-bit samples (128 = silence), as built by
// TSpecEmu.OutputWave. Returns False when there is no audio device, in which
// case the caller must throttle itself.
function AudioWriteFrame(const Buf; Count: Integer): Boolean;
procedure AudioReset;
function AudioActive: Boolean;
// Number of times the device ran dry while playing (diagnostics)
function AudioUnderruns: Integer;
// Number of non-silent samples written since AudioInit (diagnostics)
function AudioLoudSamples: Cardinal;

implementation

uses SysUtils, Math;

type
  OSStatus = Int32;
  AudioQueueRef = Pointer;

  AudioStreamBasicDescription = record
    mSampleRate: Double;
    mFormatID: UInt32;
    mFormatFlags: UInt32;
    mBytesPerPacket: UInt32;
    mFramesPerPacket: UInt32;
    mBytesPerFrame: UInt32;
    mChannelsPerFrame: UInt32;
    mBitsPerChannel: UInt32;
    mReserved: UInt32;
  end;

  PAudioQueueBuffer = ^AudioQueueBuffer;
  AudioQueueBuffer = record
    mAudioDataBytesCapacity: UInt32;
    mAudioData: Pointer;
    mAudioDataByteSize: UInt32;
    mUserData: Pointer;
    mPacketDescriptionCapacity: UInt32;
    mPacketDescriptions: Pointer;
    mPacketDescriptionCount: UInt32;
  end;

  AudioQueueOutputCallback = procedure(inUserData: Pointer; inAQ: AudioQueueRef;
    inBuffer: PAudioQueueBuffer); cdecl;

const
  kAudioFormatLinearPCM = $6C70636D; // 'lpcm'
  kLinearPCMFormatFlagIsSignedInteger = 1 shl 2;
  kLinearPCMFormatFlagIsPacked = 1 shl 3;

function AudioQueueNewOutput(constref inFormat: AudioStreamBasicDescription;
  inCallbackProc: AudioQueueOutputCallback; inUserData: Pointer;
  inCallbackRunLoop: Pointer; inCallbackRunLoopMode: Pointer; inFlags: UInt32;
  out outAQ: AudioQueueRef): OSStatus; cdecl; external name 'AudioQueueNewOutput';
function AudioQueueAllocateBuffer(inAQ: AudioQueueRef; inBufferByteSize: UInt32;
  out outBuffer: PAudioQueueBuffer): OSStatus; cdecl; external name 'AudioQueueAllocateBuffer';
function AudioQueueEnqueueBuffer(inAQ: AudioQueueRef; inBuffer: PAudioQueueBuffer;
  inNumPacketDescs: UInt32; inPacketDescs: Pointer): OSStatus; cdecl; external name 'AudioQueueEnqueueBuffer';
function AudioQueueStart(inAQ: AudioQueueRef; inStartTime: Pointer): OSStatus; cdecl; external name 'AudioQueueStart';
function AudioQueueStop(inAQ: AudioQueueRef; inImmediate: ByteBool): OSStatus; cdecl; external name 'AudioQueueStop';
function AudioQueueDispose(inAQ: AudioQueueRef; inImmediate: ByteBool): OSStatus; cdecl; external name 'AudioQueueDispose';

const
  QUEUE_BUFFERS = 3;
  QUEUE_BUFFER_SAMPLES = AUDIO_FRAME_SAMPLES div 2;  // 10 ms per device buffer
  RING_SIZE = 8192;                                  // power of two
  RING_LIMIT = 6 * AUDIO_FRAME_SAMPLES;              // ~120 ms of buffered audio

var
  Queue: AudioQueueRef = nil;
  Ring: array [0..RING_SIZE - 1] of SmallInt;
  // Free-running counters: WritePos is owned by the producer (emulator
  // thread), ReadPos by the AudioQueue callback thread.
  WritePos: Cardinal = 0;
  ReadPos: Cardinal = 0;
  ResetRequested: LongInt = 0;
  Underruns: LongInt = 0;
  LoudSamples: Cardinal = 0;
  Playing: Boolean = False;

// Runs on an AudioQueue thread that FPC did not create: no RTL heap,
// strings, exceptions or locks in here.
procedure FillBuffer(inUserData: Pointer; inAQ: AudioQueueRef; inBuffer: PAudioQueueBuffer); cdecl;
var
  Dst: PSmallInt;
  Avail, RPos: Cardinal;
  Count, i: Integer;
begin
  RPos := ReadPos;
  if ResetRequested <> 0 then
  begin
    ResetRequested := 0;
    RPos := WritePos;
    Playing := False;
  end;
  ReadBarrier;
  Avail := WritePos - RPos;
  ReadBarrier;

  Dst := inBuffer^.mAudioData;
  Count := QUEUE_BUFFER_SAMPLES;
  if Avail < Cardinal(Count) then
  begin
    if Playing then
      Inc(Underruns);
    Playing := False;
    Count := Avail;
  end
  else
    Playing := True;

  for i := 0 to Count - 1 do
  begin
    Dst^ := Ring[RPos and (RING_SIZE - 1)];
    Inc(Dst);
    Inc(RPos);
  end;
  if Count < QUEUE_BUFFER_SAMPLES then
    FillChar(Dst^, (QUEUE_BUFFER_SAMPLES - Count) * SizeOf(SmallInt), 0);

  ReadWriteBarrier;
  ReadPos := RPos;

  inBuffer^.mAudioDataByteSize := QUEUE_BUFFER_SAMPLES * SizeOf(SmallInt);
  AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil);
end;

function AudioInit: Boolean;
var
  Fmt: AudioStreamBasicDescription;
  Buf: PAudioQueueBuffer;
  i: Integer;
begin
  Result := Queue <> nil;
  if Result then Exit;

  // CoreAudio does float maths that would trap with FPC's default FPU mask
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);

  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.mSampleRate := AUDIO_SAMPLE_RATE;
  Fmt.mFormatID := kAudioFormatLinearPCM;
  Fmt.mFormatFlags := kLinearPCMFormatFlagIsSignedInteger or kLinearPCMFormatFlagIsPacked;
  Fmt.mBytesPerPacket := SizeOf(SmallInt);
  Fmt.mFramesPerPacket := 1;
  Fmt.mBytesPerFrame := SizeOf(SmallInt);
  Fmt.mChannelsPerFrame := 1;
  Fmt.mBitsPerChannel := 16;

  WritePos := 0;
  ReadPos := 0;
  ResetRequested := 0;
  Underruns := 0;
  LoudSamples := 0;
  Playing := False;

  // nil run loop: callbacks come on the queue's own thread
  if AudioQueueNewOutput(Fmt, @FillBuffer, nil, nil, nil, 0, Queue) <> 0 then
  begin
    Queue := nil;
    Exit;
  end;

  for i := 1 to QUEUE_BUFFERS do
  begin
    if AudioQueueAllocateBuffer(Queue, QUEUE_BUFFER_SAMPLES * SizeOf(SmallInt), Buf) <> 0 then
    begin
      AudioDone;
      Exit;
    end;
    FillBuffer(nil, Queue, Buf);  // primes with silence and enqueues
  end;

  if AudioQueueStart(Queue, nil) <> 0 then
  begin
    AudioDone;
    Exit;
  end;
  Result := True;
end;

procedure AudioDone;
var
  Waited: Integer;
begin
  if Queue = nil then Exit;
  // Let what is already buffered play out (at most the ring's 120 ms)
  Waited := 0;
  while (ReadPos <> WritePos) and (Waited < 250) do
  begin
    Sleep(5);
    Inc(Waited, 5);
  end;
  AudioQueueStop(Queue, True);
  AudioQueueDispose(Queue, True);
  Queue := nil;
end;

function AudioWriteFrame(const Buf; Count: Integer): Boolean;
var
  Src: PByte;
  WPos: Cardinal;
  i: Integer;
begin
  Result := Queue <> nil;
  if not Result then Exit;
  if Count > RING_LIMIT then Count := RING_LIMIT;

  // Block until there is room: this is what keeps the emulation at 50 Hz
  while Integer(RING_LIMIT - (WritePos - ReadPos)) < Count do
    Sleep(1);

  Src := @Buf;
  WPos := WritePos;
  for i := 0 to Count - 1 do
  begin
    Ring[WPos and (RING_SIZE - 1)] := (SmallInt(Src^) - 128) * 256;
    if Src^ <> 128 then Inc(LoudSamples);
    Inc(Src);
    Inc(WPos);
  end;
  WriteBarrier;
  WritePos := WPos;
end;

procedure AudioReset;
var
  Waited: Integer;
begin
  if Queue = nil then Exit;
  ResetRequested := 1;
  // Wait for the callback to drop the pending samples (one buffer, ~10 ms)
  Waited := 0;
  while (ResetRequested <> 0) and (Waited < 100) do
  begin
    Sleep(1);
    Inc(Waited);
  end;
end;

function AudioActive: Boolean;
begin
  Result := Queue <> nil;
end;

function AudioUnderruns: Integer;
begin
  Result := Underruns;
end;

function AudioLoudSamples: Cardinal;
begin
  Result := LoudSamples;
end;

end.
