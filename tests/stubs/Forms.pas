unit Forms;

// Console stand-in for the LCL Forms unit, so SpecEmu builds in tests

{$mode delphi}
interface
type
  TApplication = class
    Title: string;
    function MessageBox(Text, Caption: PChar; Flags: LongInt): LongInt;
  end;
var Application: TApplication;
implementation
function TApplication.MessageBox(Text, Caption: PChar; Flags: LongInt): LongInt;
begin WriteLn('MessageBox: ', Text); Result := 0; end;
initialization
  Application := TApplication.Create;
end.
