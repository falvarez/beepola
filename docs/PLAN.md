# Port de Beepola a macOS (Lazarus/LCL + Cocoa, arm64)

## Contexto
Beepola es una app **Delphi 2007 (VCL, Win32, strings ANSI)**. Para macOS la ruta natural es **Free Pascal + Lazarus (LCL, widgetset Cocoa)**: el núcleo (emulador Z80 `SpecEmu.pas`, ensamblador `Asm*.pas`, motores `*_Engine.pas`, `STSong`, `SongRipper`) es Pascal puro y compila casi tal cual en `{$mode delphi}`. Los bloqueos reales son pocos y localizados:

| Dependencia Windows | Dónde | Sustituto |
|---|---|---|
| Audio WaveOut (`MMSystem`, `waveOutOpen/Write`, `GlobalAlloc`) | `SpecEmu.pas`, `frmSTMainWnd.pas` (FormCreate/Destroy) | Nueva unidad `BeeperAudio.pas` con CoreAudio **AudioQueue** |
| Temporización `QueryPerformanceCounter`, `timeGetTime`, `timeBeginPeriod` | `SpecEmu.Interrupt`, `frmSTMainWnd` | Ritmo marcado por el buffer de audio (bloquear cuando está lleno) + fallback `GetTickCount64`/`Sleep` |
| `PostMessage(WM_USER_*)` desde el hilo reproductor | `PlayerThread.pas` → `WM_NewPattern/PatternTick/SongEnd` | `TThread.Queue` llamando a métodos del form |
| Registro (`TRegistry`) | `RegSettings.pas`, `MRUList.pas` | `TIniFile` en `GetAppConfigDir` (~/Library/Preferences/…) |
| `FindFirstFile`, `GetFileVersionInfo` | `GrokUtils.pas` | `FileUtil.FileSize`; versión como constante |
| `ShellExecute(iexplore…)` | `frmSTMainWnd.pas:2421` | `OpenURL`/`OpenDocument` a la ayuda local empaquetada (`help/`, copiada de la 1.08.01) |
| `TJvFilenameEdit` (JVCL) | un `.dfm` | `TFileNameEdit` (unidad `EditBtn`) |
| `.dfm` VCL | 15 formularios (texto) | `.lfm` limpiados de propiedades VCL no soportadas |
| Recursos `BeepolaData.RES` (`z80.tab`, `*.img`) vía `TResourceStream` | `Assemb.pas`, `SpecEmu.LoadImage` | Se mantiene: FPC enlaza `.res` en Mach-O; `{$R BeepolaData.res}` |

El plugin de motores DLL (`BeepolaSDK.pas`, `engines/FuzzClick`) no se usa desde la app (no hay `LoadLibrary`) → se deja fuera.

Nota: el código fuente es v1.06.02+trunk; el `.exe` incluido es v1.08.01. Se compila lo que hay en el repo.

## Pasos

1. **Toolchain mínimo** (las Command Line Tools de Xcode ya están instaladas):
   - `brew install fpc` (único paquete del sistema).
   - Código fuente de Lazarus (release estable) descargado en `~/opt/lazarus` (sin IDE); `make lazbuild` y compilar LCL con `LCL_PLATFORM=cocoa CPU_TARGET=aarch64`.
   - Si FPC 3.2.2 falla al enlazar con el `ld` actual: probar `-k-ld_classic`; si no basta, compilar FPC fixes desde fuente en `~/opt/fpc` usando el de brew como bootstrap.
   - Verificar `fpc -i`, `~/opt/lazarus/lazbuild --version`.
   - Comprobado (2026-11-13): con FPC 3.2.2 y `ld-27106` la LCL Cocoa no enlaza (`malformed method list atom … cocoawsextctrls.o`) y `-k-ld_classic` se ignora (ya no existe). Hace falta FPC ≥ 3.2.4 (`release_3_2_4`).
   - Toolchain resultante: FPC 3.2.4 en `~/opt/fpc` (compilado con el de brew: `make all FPC=/opt/homebrew/bin/ppca64 OPT="-XR$(xcrun --show-sdk-path) -Fl$(xcrun --show-sdk-path)/usr/lib"`; `make install PREFIX=~/opt/fpc`; `~/opt/fpc/etc/fpc.cfg` con `samplecfg` más `-XR`/`-Fl` del SDK). `lazbuild` recompilado con `make lazbuild LCL_PLATFORM=cocoa FPC=~/opt/fpc/bin/fpc` y `CompilerFilename` de `~/.lazarus/environmentoptions.xml` apuntando a `~/opt/fpc/bin/fpc`.
2. **Proyecto Lazarus**: crear `Beepola.lpi` / `Beepola.lpr` (desde `Beepola.dpr`: `Interfaces` antes de `Forms`, quitar `MainFormOnTaskbar`, `{$R BeepolaData.res}`, sin `Beepola.res` de Windows). Widgetset cocoa, target `aarch64-darwin`, opción “Create application bundle”. Mantener los archivos Delphi intactos para poder seguir compilando en Windows donde sea barato (`{$IFDEF FPC}`), pero sin obsesionarse.
3. **Formularios**: copiar cada `*.dfm` → `*.lfm` (script en scratchpad), cambiar `{$R *.dfm}` → `{$R *.lfm}`, eliminar propiedades que LCL rechaza (`OldCreateOrder`, `Ctl3D`, `ExplicitWidth/Height/Left/Top`, `TextHeight`, `PixelsPerInch` se tolera, etc.) iterando con los errores de carga. `TJvFilenameEdit` → `TFileNameEdit`. Glyphs/Picture.Data (BMP) los lee LCL directamente.
4. **Usos de unidades**: en cada `frm*.pas` sustituir `Windows, Messages` por `LCLIntf, LCLType, LMessages`; `Variants` se mantiene. Añadir `{$mode delphi}` (vía opción de proyecto `-Mdelphi`).
5. **Audio — nueva `BeeperAudio.pas`**:
   - Declaraciones mínimas de AudioToolbox (`AudioQueueNewOutput`, `AllocateBuffer`, `EnqueueBuffer`, `Start`, `Stop`, `Dispose`) o `MacOSAll` si están disponibles; `{$linkframework AudioToolbox}`.
   - Formato 44100 Hz, mono, 16-bit signed (convertir el byte 128±k actual).
   - Ring buffer thread-safe (~6 frames de 882 muestras = 120 ms); callback de AudioQueue lo consume, rellena con silencio si vacío.
   - API: `AudioInit`, `AudioDone`, `AudioWriteFrame(const buf; n)` (bloquea mientras el ring está lleno → actúa como reloj a 50 Hz), `AudioReset`.
   - Instancia global abierta en `TSTMainWnd.FormCreate`, cerrada en `FormDestroy`.
6. **`SpecEmu.pas`**: quitar `MMSystem`/`WavHdr`/`ghMem`/`gpMem`; constructor sin `hWaveOut` (o parámetro ignorado); `OutputWave` → `AudioWriteFrame`; `Interrupt` usa el bloqueo del audio para el throttle (con fallback temporal si no hay audio); `CopyMemory` → `Move`; `ResetWaveBuffers` → `AudioReset`. La exportación WAV (`OutputWaveFile`) no cambia.
7. **`PlayerThread.pas`**: eliminar `HMsgWnd`/`WaveOutHandle`; añadir `MsgTarget: TSTMainWnd`-agnóstico vía tres eventos `TThreadMethod` (`OnNewPattern`, `OnPatternTick`, `OnSongEnd`) disparados con `Queue(...)`. En `frmSTMainWnd.pas` convertir `WM_NewPattern/WM_PatternTick/WM_SongEnd(var Msg)` en métodos sin parámetros y asignarlos en los 3 sitios donde se crea `ZXPlay` (~2976, 3028, 3108).
8. **Settings**: reescribir `RegSettings.pas` y `MRUList.pas` sobre `TIniFile` (`GetAppConfigDir(False) + 'beepola.ini'`), misma interfaz pública.
9. **`GrokUtils.pas`**: `Sto_GetFileSize` con `FileUtil.FileSize`; `GetAppVersionInfo` devuelve constante `'1.06.02'` (o leída de `fileinfo` si se rellena la versión en el `.lpi`).
10. **`frmSTMainWnd.pas` varios**: quitar `timeBeginPeriod/timeEndPeriod/timeGetDevCaps`; ayuda → `OpenDocument(<bundle>/Contents/Resources/help/index.html)`; `GetSystemMetrics` ya existe en `LCLIntf`; `Application.MessageBox(..., MB_*)` funciona con `LCLType`.
11. **Teclado Mac**: los portátiles Mac no tienen `Insert` ni teclado numérico. Añadir alternativas sin quitar las originales: `Insert` también con **Ctrl+Enter** (o Fn+Enter → `VK_INSERT` no existe; usar Ctrl+I), y octava con **Ctrl+1…5** además de `VK_NUMPAD1..5`. En menús, convertir en runtime los atajos Ctrl+X a **Cmd+X** (`ssCtrl`→`ssMeta`) bajo `{$IFDEF DARWIN}`.
12. **Bundle**: `lazbuild Beepola.lpi` → `Beepola.app`; script `build_macos.sh` que compila, copia el ejecutable dentro del bundle, añade `Info.plist`, icono `Beepola.icns` (generado de `Beepola.ico` con `sips`/`iconutil`) y `help/` en `Resources`; firma ad-hoc `codesign -s -`.
13. **Ajustes visuales** tras primera ejecución: fuentes (`MS Sans Serif` → fuente del sistema, mantener `Courier New` para la rejilla), alturas de `TStringGrid`, owner-draw de `grdPattern/grdSong`, `pbxLoopStart`.

## Archivos críticos
- Nuevos: `Beepola.lpi`, `Beepola.lpr`, `BeeperAudio.pas`, `*.lfm`, `build_macos.sh`.
- Modificados: `SpecEmu.pas`, `PlayerThread.pas`, `frmSTMainWnd.pas`, `RegSettings.pas`, `MRUList.pas`, `GrokUtils.pas`, `SongRipper.pas`, `frmExportWavDlg.pas` (usa `STMainWnd.hWaveOut`), resto de `frm*.pas` (sólo cláusulas `uses` y `{$R}`).

## Verificación
1. `lazbuild Beepola.lpi` sin errores; `./build_macos.sh` produce `Beepola.app`; `open Beepola.app` arranca y muestra la ventana principal sin excepciones de carga de `.lfm`.
2. Abrir un `.bbsong` (crear uno nuevo si no hay ejemplos), tocar notas con el teclado → suena por el altavoz; reproducir patrón y canción con cada motor (SFX, TMB, MSD, P1D, P1S, SVG, RMB, PLP) → audio a tempo correcto y resaltado de fila avanzando (eventos del hilo), Stop limpio.
3. Exportar WAV y comprobar duración/sonido con `afplay`.
4. Compilar a `.tap`/`.asm` desde el diálogo Compile y comparar el binario con el generado por `Beepola.exe` original (si se dispone de Wine/Windows) o al menos cargarlo en un emulador (Fuse) y verificar que suena.
5. Guardar opciones y MRU, reiniciar app → persisten en el `.ini`.
