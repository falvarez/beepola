program render;

// Render a song with one engine to a WAV file, to compare emulator changes:
//
//   render <engine> <song.bbsong> <out.wav> <frames> [pattern]
//
// <engine> is the TEngine ordinal (0 SFX, 1 TMB, 2 MSD, 3 P1D, 4 P1S, 5 SVG,
// 6 RMB, 7 PLP, 9 ABOUT); 'pattern' plays the song's first pattern only.

{$mode delphi}

uses SysUtils, STSong, STPatterns, SpecEmu;

{$R ../BeepolaData.RES}

var
  Song: TSTSong;
  Emu: TSpecEmu;
  i: Integer;
begin
  Song := TSTSong.Create;
  Song.LoadFile(ParamStr(2));
  Emu := TSpecEmu.Create(0);
  Emu.Engine := TEngine(StrToInt(ParamStr(1)));
  if ParamStr(5) = 'pattern' then
    Emu.LoadPlayerPattern(Song.Pattern[Song.SongLayout[0]], Song.SvgPatternData[Song.SongLayout[0]], Song)
  else
    Emu.LoadPlayerSong(Song);
  Emu.WavOutputFile := ParamStr(3);
  Emu.Register_SP := $7FF0;
  Emu.Register_PC := $8000;
  for i := 1 to StrToInt(ParamStr(4)) do
    Emu.Exec(true);
  Emu.CloseWaveFile;
  Emu.Free;
end.
