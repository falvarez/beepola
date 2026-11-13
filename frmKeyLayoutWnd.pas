unit frmKeyLayoutWnd;

interface

uses
  {$IFDEF FPC}LCLIntf, LCLType, LMessages,{$ELSE}Windows, Messages,{$ENDIF} SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TKeyboardLayoutWnd = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    Label14: TLabel;
    Label15: TLabel;
    Label16: TLabel;
    Label17: TLabel;
    Label18: TLabel;
    Label19: TLabel;
    Label20: TLabel;
  private
    { Private declarations }
{$IFDEF DARWIN}
    procedure MacFitWidth(Sender: TObject);
  protected
    procedure Loaded; override;
{$ENDIF}
  public
    { Public declarations }
  end;

var
  KeyboardLayoutWnd: TKeyboardLayoutWnd;

implementation

{$IFDEF FPC}{$R *.lfm}{$ELSE}{$R *.dfm}{$ENDIF}

{$IFDEF DARWIN}
// Mention the alternatives frmSTMainWnd accepts on Mac keyboards, which
// lack Insert, a forward Delete key and a numeric keypad
procedure TKeyboardLayoutWnd.Loaded;
var
  i: integer;
  L: TLabel;
begin
  inherited;
  for i := 0 to ComponentCount - 1 do
    if Components[i] is TLabel then
    begin
      L := Components[i] as TLabel;
      L.Caption := StringReplace(L.Caption, '[Ins]', '[Ins]/[Ctrl]+[I]', []);
      L.Caption := StringReplace(L.Caption, '[Del]', '[Del]/[Backspace]', []);
    end;
  Label9.Caption := StringReplace(Label9.Caption, 'Keys 1- 5', 'Keys 1- 5 or [Ctrl]+[1]-[5]', []);
  OnShow := MacFitWidth;
end;

// Widen the window to the longest line, which macOS renders wider
procedure TKeyboardLayoutWnd.MacFitWidth(Sender: TObject);
var
  i, W: integer;
begin
  W := ClientWidth;
  for i := 0 to ControlCount - 1 do
    if Controls[i].Left + Controls[i].Width + 12 > W then
      W := Controls[i].Left + Controls[i].Width + 12;
  ClientWidth := W;
end;
{$ENDIF}

end.
