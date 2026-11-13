unit Dialogs;

// Console stand-in for the LCL Dialogs unit, so SpecEmu builds in tests

{$mode delphi}
interface
procedure ShowMessage(const S: string);
implementation
procedure ShowMessage(const S: string); begin WriteLn('ShowMessage: ', S); end;
end.
