program cpm;

// Minimal CP/M environment to run the zexdoc/zexall Z80 instruction
// exercisers on TSpecEmu:
//
//   cpm zexdoc.com           all tests
//   ONLY=12,49 cpm zexdoc.com   just those tests (0-based)

{$mode delphi}

uses SysUtils, Classes, SpecEmu;

var
  Emu: TSpecEmu;
  F: TFileStream;
  Buf: array of Byte;
  i, t: Integer;
  Addr: Word;
  Steps: Int64;
  T0: QWord;
  sOnly: string;
  Tests: array of Word;
begin
  Emu := TSpecEmu.Create(0);
  Emu.WavOutputFile := '/dev/null';  // write frames instead of pacing to audio
  Emu.ROMProtected := False;         // CP/M programs live at $0100

  F := TFileStream.Create(ParamStr(1), fmOpenRead);
  SetLength(Buf, F.Size);
  F.Read(Buf[0], F.Size);
  F.Free;
  for i := 0 to 65535 do Emu.Memory[i] := 0;
  for i := 0 to High(Buf) do Emu.Memory[$100 + i] := Buf[i];
  Emu.Memory[5] := $C9;                        // BDOS entry: RET (trapped below)
  Emu.Memory[6] := $00; Emu.Memory[7] := $F0;  // top of the TPA
  Emu.Memory[$38] := $FB;                      // the 50 Hz IM 1 interrupt: EI; RET
  Emu.Memory[$39] := $C9;

  // The exercisers keep a 0-terminated table of test pointers at $013A
  sOnly := GetEnvironmentVariable('ONLY');
  if sOnly <> '' then
  begin
    with TStringList.Create do
    try
      CommaText := sOnly;
      SetLength(Tests, Count);
      for t := 0 to Count - 1 do
        Tests[t] := Emu.Memory[$13A + StrToInt(Strings[t]) * 2] or
                    (Emu.Memory[$13B + StrToInt(Strings[t]) * 2] shl 8);
    finally
      Free;
    end;
    for t := 0 to High(Tests) do
    begin
      Emu.Memory[$13A + t * 2] := Tests[t] and $FF;
      Emu.Memory[$13B + t * 2] := Tests[t] shr 8;
    end;
    Emu.Memory[$13A + Length(Tests) * 2] := 0;
    Emu.Memory[$13B + Length(Tests) * 2] := 0;
  end;

  Emu.Register_PC := $100;
  Emu.Register_SP := $F000;
  Steps := 0;
  T0 := GetTickCount64;
  while Emu.Register_PC <> 0 do      // warm boot ends the program
  begin
    if Emu.Register_PC = 5 then
      case Emu.Register_C of
        2: Write(Chr(Emu.Register_DE and $FF));
        9: begin
             Addr := Emu.Register_DE;
             while Chr(Emu.Memory[Addr]) <> '$' do
             begin
               Write(Chr(Emu.Memory[Addr]));
               Inc(Addr);
             end;
             Flush(Output);
           end;
      end;
    Emu.Exec(false);
    Inc(Steps);
  end;
  WriteLn;
  WriteLn(Format('[%d instructions, %.1f s]', [Steps, (GetTickCount64 - T0) / 1000]));
  Emu.Free;
end.
