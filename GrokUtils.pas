unit GrokUtils;

interface

uses Classes;

function Sto_GetFileSize(const FileName: String): Int64;
procedure GetAppVersionInfo(var sInfo: string);
function StreamGetString(F: TStream; out bEOF: boolean): string;
{$IFDEF FPC}
// Ini file that replaces the Windows registry keys
function SettingsFileName: string;
{$ENDIF}

implementation

{$IFDEF FPC}
uses SysUtils;
{$ELSE}
uses Windows, SysUtils, Forms;
{$ENDIF}

////////////////////////////////////////////////////////////////
// this function determines the size of a file in bytes, the size
// can be more than 2 GB.
function Sto_GetFileSize(const FileName: String): Int64;
{$IFDEF FPC}
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(FileName, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end;
end;
{$ELSE}
var
  myFile: THandle;
  myFindData: TWin32FindData;
begin
  // set default value
  Result := 0;
  // get the file handle.
  myFile := FindFirstFile(PChar(FileName), myFindData);
  if (myFile <> INVALID_HANDLE_VALUE) then
  begin
    Windows.FindClose(myFile);
    Int64Rec(Result).Lo := myFindData.nFileSizeLow;
    Int64Rec(Result).Hi := myFindData.nFileSizeHigh;
  end;
end;
{$ENDIF}

{$IFDEF FPC}
procedure GetAppVersionInfo(var sInfo: string);
begin
  // No version resource on macOS: matches the 1.06.02 source tree
  sInfo := '1.06.02';
end;
{$ELSE}
procedure GetAppVersionInfo(var sInfo: string);
var
  VerInfo: PChar;
  VerInfoSize: integer;
  Discard: cardinal;
  FileVer: PChar;
  DataLen: cardinal;
begin
  VerInfoSize := GetFileVersionInfoSize(PChar(Application.ExeName),Discard);
  if VerInfoSize > 0 then
  begin
    VerInfo := AllocMem(VerInfoSize);
    GetFileVersionInfo(PChar(Application.ExeName),0,VerInfoSize,VerInfo);
    VerQueryValue(VerInfo,Pchar('\' + #0),Pointer(FileVer),DataLen);

    sInfo := IntToStr((PVSFIXEDFILEINFO(FileVer).dwFileVersionMS and $FFFF0000) shr 16) + '.' +
             Copy(IntToStr((PVSFIXEDFILEINFO(FileVer).dwFileVersionMS and $FFFF)+100),2,2) + '.' +
             Format('%.2d',[(PVSFIXEDFILEINFO(FileVer).dwFileVersionLS and $FFFF0000) shr 16]);

    FreeMem(VerInfo,VerInfoSize);
  end
  else
    sInfo := '0.0.0.0000';
end;
{$ENDIF}

{$IFDEF FPC}
function SettingsFileName: string;
var
  sDir: string;
begin
  sDir := GetAppConfigDir(False);
  ForceDirectories(sDir);
  Result := IncludeTrailingPathDelimiter(sDir) + 'beepola.ini';
end;
{$ENDIF}

function StreamGetString(F: TStream; out bEOF: boolean): string;
var
  i, iLen: integer;
  c: array [0..1026] of char;
begin
  bEOF := true;

  iLen := F.Read(c,1024);
  for i := 0 to iLen-2 do begin
    if (c[i] = #13) and (c[i+1] = #10) then
    begin
      F.Seek(-iLen+i+2,soFromCurrent);
      Result := Copy(c,0,i);
      bEOF := false;
      break;
    end;
  end;

  if bEof then
    Result := Copy(c,0,iLen);
end;

end.
