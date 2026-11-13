unit MacLayout;

// Layout fixes for forms designed with the Windows VCL when they run on the
// Cocoa widgetset.

{$mode delphi}

interface

uses Forms;

// Applies the fixes below to every group box and check box of the form:
//
// VCL places group box children relative to the box's outer corner, below a
// caption it draws on the border; Cocoa draws the title above the border and
// starts the client area lower, so children end up pushed down and clipped.
// Move them up and grow the boxes (and their parents) where still needed.
//
// Some check boxes have no caption and a separate label right next to the
// 13 px VCL box; the wider Cocoa box overlaps that label, so move it right.
procedure FixVCLLayout(F: TCustomForm);

implementation

uses Classes, Controls, StdCtrls, ComCtrls;

const
  COCOA_GROUPBOX_CHROME = 26;  // Height - ClientHeight of a Cocoa TGroupBox
  CHILD_MARGIN = 4;
  COCOA_CHECKBOX_WIDTH = 20;  // box plus the gap before its label

// Move the controls of Parent that sit below Y down by Delta, except those
// anchored to the bottom only, which follow the parent when it grows.
procedure MoveControlsBelow(Parent: TWinControl; Skip: TControl; Y, Delta: integer);
var
  i: integer;
  C: TControl;
begin
  for i := 0 to Parent.ControlCount - 1 do
  begin
    C := Parent.Controls[i];
    if (C <> Skip) and (C.Top >= Y) and
       not ((akBottom in C.Anchors) and not (akTop in C.Anchors)) then
      C.Top := C.Top + Delta;
  end;
end;

procedure GrowControl(C: TControl; Delta: integer);
var
  OldBottom: integer;
  P: TWinControl;
begin
  while C <> nil do
  begin
    OldBottom := C.Top + C.Height;
    C.Height := C.Height + Delta;
    P := C.Parent;
    if P = nil then exit;
    MoveControlsBelow(P, C, OldBottom, Delta);
    if P is TCustomForm then
    begin
      P.ClientHeight := P.ClientHeight + Delta;
      exit;
    end;
    // A tab sheet is sized by its page control: grow that instead
    if P is TTabSheet then
      C := P.Parent
    else
      C := P;
  end;
end;

procedure FixGroupBox(G: TGroupBox);
var
  i, MinTop, MaxBottom, Shift, Need: integer;
begin
  if G.ControlCount = 0 then exit;
  MinTop := MaxInt;
  MaxBottom := 0;
  for i := 0 to G.ControlCount - 1 do
  begin
    if G.Controls[i].Top < MinTop then MinTop := G.Controls[i].Top;
    if G.Controls[i].Top + G.Controls[i].Height > MaxBottom then
      MaxBottom := G.Controls[i].Top + G.Controls[i].Height;
  end;

  Shift := MinTop - CHILD_MARGIN;
  if Shift > 0 then
    for i := 0 to G.ControlCount - 1 do
      G.Controls[i].Top := G.Controls[i].Top - Shift
  else
    Shift := 0;

  Need := MaxBottom - Shift + CHILD_MARGIN - (G.Height - COCOA_GROUPBOX_CHROME);
  if Need > 0 then
    GrowControl(G, Need);
end;

procedure FixCheckBoxLabel(C: TCheckBox);
var
  i: integer;
  L: TControl;
begin
  if (C.Caption <> '') or (C.Parent = nil) then exit;
  for i := 0 to C.Parent.ControlCount - 1 do
  begin
    L := C.Parent.Controls[i];
    if (L is TLabel) and (Abs(L.Top - C.Top) <= 4) and
       (L.Left >= C.Left) and (L.Left < C.Left + COCOA_CHECKBOX_WIDTH) then
      L.Left := C.Left + COCOA_CHECKBOX_WIDTH;
  end;
end;

procedure FixVCLLayout(F: TCustomForm);
var
  i: integer;
begin
  F.DisableAutoSizing;
  try
    for i := 0 to F.ComponentCount - 1 do
      if F.Components[i] is TGroupBox then
        FixGroupBox(F.Components[i] as TGroupBox)
      else if F.Components[i] is TCheckBox then
        FixCheckBoxLabel(F.Components[i] as TCheckBox);
  finally
    F.EnableAutoSizing;
  end;
end;

end.
