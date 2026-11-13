unit MacKeyboard;

// Active keyboard layout on macOS, reported with the Windows layout ids that
// frmSTMainWnd uses to map note keys (AZERTY, QWERTZ, otherwise QWERTY).

{$mode delphi}
{$linkframework Carbon}  // Text Input Sources (TIS) live in HIToolbox

interface

const
  LAYOUT_QWERTY = $04090409;  // US English
  LAYOUT_AZERTY = $040C040C;  // French
  LAYOUT_QWERTZ = $04070407;  // German

// Input source id of the current layout, e.g. 'com.apple.keylayout.French'
function MacKeyboardLayoutID: string;
function LayoutIDToWindowsLayout(const ID: string): Cardinal;
// Same as Windows' GetKeyboardLayout for the layouts Beepola knows
function MacKeyboardLayout: Cardinal;

implementation

uses SysUtils, CFBase, CFString, TextInputSources;

const
  APPLE_PREFIX = 'com.apple.keylayout.';
  AZERTY_LAYOUTS: array [0..3] of string =
    ('French', 'French-PC', 'French-numerical', 'Belgian');
  QWERTZ_LAYOUTS: array [0..8] of string =
    ('German', 'German-DIN-2137', 'Austrian', 'SwissGerman', 'SwissFrench',
     'Slovenian-QWERTZ', 'Croatian', 'Croatian-PC', 'Polish');

function MacKeyboardLayoutID: string;
var
  Src: TISInputSourceRef;
  ID: CFStringRef;
  Buf: array [0..255] of AnsiChar;
begin
  Result := '';
  Src := TISCopyCurrentKeyboardLayoutInputSource;
  if Src = nil then exit;
  ID := CFStringRef(TISGetInputSourceProperty(Src, kTISPropertyInputSourceID));
  if (ID <> nil) and CFStringGetCString(ID, @Buf[0], SizeOf(Buf), kCFStringEncodingUTF8) then
    Result := Buf;
  CFRelease(Src);
end;

function LayoutIDToWindowsLayout(const ID: string): Cardinal;
var
  sName: string;
  i: integer;
begin
  Result := LAYOUT_QWERTY;
  if Copy(ID, 1, Length(APPLE_PREFIX)) <> APPLE_PREFIX then exit;
  sName := Copy(ID, Length(APPLE_PREFIX) + 1, MaxInt);
  for i := Low(AZERTY_LAYOUTS) to High(AZERTY_LAYOUTS) do
    if sName = AZERTY_LAYOUTS[i] then Exit(LAYOUT_AZERTY);
  for i := Low(QWERTZ_LAYOUTS) to High(QWERTZ_LAYOUTS) do
    if sName = QWERTZ_LAYOUTS[i] then Exit(LAYOUT_QWERTZ);
end;

function MacKeyboardLayout: Cardinal;
begin
  Result := LayoutIDToWindowsLayout(MacKeyboardLayoutID);
end;

end.
