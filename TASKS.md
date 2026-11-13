# Tareas: port de Beepola a macOS

Plan completo en [docs/PLAN.md](docs/PLAN.md). Tareas en orden de ejecución; cada una indica cómo verificarla.

## 1. Toolchain

- [x] Instalar FPC con Homebrew (`brew install fpc`).
  Verificación: `fpc -i` muestra la versión y `fpc -iTP` incluye `aarch64`.
- [x] Descargar el código fuente estable de Lazarus en `~/opt/lazarus` y compilar `lazbuild` (`make lazbuild`).
  Verificación: `~/opt/lazarus/lazbuild --version` imprime la versión.
  Hecho: tag `lazarus_4_8`, `make lazbuild LCL_PLATFORM=cocoa`; enlaza sin `-k-ld_classic`.
- [ ] Compilar un "hola mundo" LCL/Cocoa de prueba (un form con un botón) en el scratchpad con `lazbuild --ws=cocoa`.
  Verificación: el binario arranca y muestra la ventana. Si el enlazado falla, probar `-k-ld_classic` y anotar el flag necesario en `docs/PLAN.md`.
  BLOQUEADA: con FPC 3.2.2 (brew) el enlazado falla con el `ld` actual (ld-27106): `malformed method list atom 'ltmp5' (cocoawsextctrls.o), fixups found beyond the number of method entries`; `-k-ld_classic` ya no funciona (`-ld_classic is no longer supported and will be ignored`). Solución prevista en el plan: compilar FPC 3.2.4 (tag `release_3_2_4`) desde fuente en `~/opt/fpc` con el de brew como bootstrap, recompilar `lazbuild`/LCL con él y reintentar. Pendiente de autorizar la descarga y compilación.

## 2. Esqueleto del proyecto

- [x] Crear `Beepola.lpr` (a partir de `Beepola.dpr`: `Interfaces` antes de `Forms`, sin `MainFormOnTaskbar`, `{$R BeepolaData.res}`) y `Beepola.lpi` (modo Delphi, widgetset cocoa, aarch64-darwin, `-k-ld_classic` si hizo falta).
  Verificación: `lazbuild Beepola.lpi` empieza a compilar unidades (los errores en unidades concretas son aceptables en este punto).
  Hecho: sin `{$R BeepolaData.res}` en el `.lpr` porque ya lo incluye `frmSTMainWnd.pas`; `BeepolaSDK` fuera; sin `-k-ld_classic` (no sirve). Falla en `frmSTMainWnd.pas` por la unidad `Windows`, como se esperaba.
- [x] Añadir a `.gitignore` las salidas de compilación (`lib/`, `*.o`, `*.ppu`, `Beepola.app/`, binario `Beepola`).
  Verificación: tras un build, `git status` no muestra artefactos.

## 3. Núcleo sin interfaz gráfica

- [x] Hacer que compilen las unidades puras: `AsmTypes`, `AsmUtils`, `AsmPass1`, `AsmPass2`, `Assemb`, `STPatterns`, `STInstruments`, `STSong`, `*_Engine.pas`.
  Verificación: `fpc -Mdelphi -Fu. <unidad>.pas` compila cada unidad sin errores.
  Hecho: compilan las 16 sin errores ni avisos en cuanto `GrokUtils` dejó de usar `Windows`; no hizo falta tocarlas.
- [x] `GrokUtils.pas`: `Sto_GetFileSize` con `FileSize` de FPC; `GetAppVersionInfo` devuelve una constante.
  Verificación: `fpc -Mdelphi GrokUtils.pas` compila; un programa de prueba en el scratchpad imprime el tamaño correcto de `z80.tab` (14096).
  Hecho: bajo `{$IFDEF FPC}`, `FindFirst`/`TSearchRec.Size` de `SysUtils` (Int64, sin depender de LazUtils) y versión `'1.06.02'`; el código Windows se conserva en `{$ELSE}`.
- [x] Comprobar que `TResourceStream` lee `BeepolaData.RES` en Darwin.
  Verificación: un programa de prueba con `{$R BeepolaData.res}` carga `z80_tab` (14096 bytes) y `sfx_img` (65536 bytes).
  Hecho: FPC enlaza el `.RES` de Windows en Mach-O; los 9 recursos cargan con su tamaño y su contenido es idéntico (`cmp`) a los ficheros fuente. No hay que cambiar el `.RES`.

## 4. Audio

- [ ] Crear `BeeperAudio.pas` (AudioQueue, 44100 Hz mono 16-bit, ring buffer de unos 6 frames, `AudioInit/AudioDone/AudioWriteFrame/AudioReset`).
  Verificación: un programa de prueba en consola genera 2 s de onda cuadrada a 440 Hz en frames de 882 muestras; se oye limpia y dura unos 2 s (`time`).
  Hecho salvo la escucha: la prueba tarda 2,02 s (1,88 s escribiendo + vaciado del ring) y da 0 underruns mientras suena (el único que cuenta es el vaciado final). Dos trampas resueltas: `constref` para el `AudioStreamBasicDescription` (con `cdecl`, `const` pasa el record por valor) y `SetExceptionMask` (CoreAudio dispara excepciones FP que FPC desenmascara por defecto). PENDIENTE: confirmar a oído que suena limpia.
- [ ] `SpecEmu.pas`: quitar `MMSystem`/WaveOut/`GlobalAlloc`; `OutputWave` usa `AudioWriteFrame`; throttle en `Interrupt` basado en el bloqueo del audio, con fallback por `GetTickCount64`/`Sleep`; `CopyMemory` → `Move`.
  Verificación: `fpc -Mdelphi SpecEmu.pas` compila; un programa de prueba carga `sfx_img`, pone una nota y ejecuta 100 interrupciones → se oye la nota durante unos 2 s.
  Hecho salvo la escucha: compila contra la LCL (o contra stubs de `Forms`/`Dialogs`/`LCLType` en la prueba de consola, porque la LCL Cocoa no enlaza todavía, ver 1.3). 100 interrupciones: 1,88 s con audio (+0,12 s de vaciado), 0 underruns; sin dispositivo, el reloj de reserva tarda 1,98 s. Renderizada a WAV, la nota suena los 2 s. `ResetWaveBuffers` NO llama a `AudioReset`: se usa al final de cada nota tocada y cortaría su cola (Windows tampoco descartaba el audio en cola). PENDIENTE: confirmar a oído.

## 5. Hilo de reproducción y settings

- [x] `PlayerThread.pas`: sustituir `PostMessage`/`HMsgWnd`/`WaveOutHandle` por eventos `OnNewPattern/OnPatternTick/OnSongEnd` disparados con `TThread.Queue`.
  Verificación: la unidad compila; el test se hace en la tarea de reproducción de la sección 7.
  Hecho: eventos `TThreadMethod` encolados con `Queue(nil, …)` (sin ligar al hilo, para que `OnSongEnd` llegue aunque ya se haya liberado); `WaveOutHandle`/`HMsgWnd` y los `WM_USER_*` solo quedan bajo `{$IFNDEF FPC}`. `inherited Create(CreateSuspended)` porque el `TThread.Create` de FPC tiene un parámetro más. Prueba de consola: 1 s de canción SFX → 1 OnNewPattern, 51 OnPatternTick y OnSongEnd entregado tras `WaitFor`/`Free`.
- [x] Reescribir `RegSettings.pas` y `MRUList.pas` sobre `TIniFile` en `GetAppConfigDir`, con la misma interfaz pública.
  Verificación: un programa de prueba guarda las opciones y 3 entradas MRU, las relee y las imprime; existe `~/.config/…/beepola.ini` (o la ruta que devuelva `GetAppConfigDir`).
  Hecho: secciones `[Options]` y `[MRU]` con las mismas claves que el registro; la ruta sale de `SettingsFileName` (nuevo en `GrokUtils`). FPC devuelve `~/.config/<ejecutable>/`, así que la app usará `~/.config/Beepola/beepola.ini`. Prueba: se guardan, se releen y la MRU conserva el orden.

## 6. Formularios

- [x] Script (en el scratchpad) que convierte `*.dfm` → `*.lfm` y elimina las propiedades VCL no soportadas; cambiar `{$R *.dfm}` → `{$R *.lfm}` en cada `frm*.pas`.
  Verificación: existen 15 `.lfm`; `grep -l 'OldCreateOrder\|Explicit' *.lfm` no devuelve nada.
  Hecho: se eliminan `OldCreateOrder`, `TextHeight`, `DesignSize` (multilínea), `ParentFlat` y `Explicit*` (112 líneas, cuadra con el recuento previo). Los `.dfm` se conservan y los `.pas` usan `{$IFDEF FPC}{$R *.lfm}{$ELSE}{$R *.dfm}{$ENDIF}`. Nota: LCL 4.8 ya ignoraba casi todas al cargar; `ParentFlat` no existe en LCL. El resto (p. ej. `TImageList.Bitmap` en formato Delphi, que LCL dice leer) se comprobará al arrancar (sección 7).
- [x] Ajustar la cláusula `uses` de los diálogos simples (`Windows, Messages` → `LCLIntf, LCLType, LMessages`): CopyPattern, TransposePattern/Song, SwapChannels, PatternAppend, AdjustSongTempo, Options, KeyLayout, SongInfo, About.
  Verificación: cada unidad compila con `lazbuild` (los errores restantes quedan solo en `frmSTMainWnd`, `frmCompileDlg`, `frmExportWavDlg`, `frmImportVTIIFileDlg` y `frmSongRipper`).
  Hecho: `{$IFDEF FPC}LCLIntf, LCLType, LMessages,{$ELSE}Windows, Messages,{$ENDIF}`. `frmKeyLayoutWnd` compila entero; los otros 9 llegan hasta `uses frmSTMainWnd` y se paran ahí, así que su implementación se valida en la tarea de `frmSTMainWnd`. En About: fuera JVCL/`jpeg`/`ToolWin` (no se usaban), `WM_USER_NEWPATTERN` → `OnNewPattern`, `Suspend` → `Terminate` (en Unix no se puede suspender otro hilo) y «Saša Pušica» como UTF-8 (el fuente está en CP1252).
- [x] `TJvFilenameEdit` → `TFileNameEdit` (unidad `EditBtn`) en el `.lfm` y el `.pas` correspondientes.
  Verificación: la unidad compila.
  Hecho: en el `.lfm` fuera `AddQuotes` y `BevelOuter` (el resto de propiedades existen en `TFileNameEdit`); en el `.pas`, tipo y `uses` bajo `{$IFDEF FPC}`. Compila (ver la tarea siguiente).
- [x] `frmExportWavDlg`, `frmCompileDlg`, `frmImportVTIIFileDlg`, `frmSongRipper`, `SongRipper.pas`: `uses` y quitar las referencias a `hWaveOut`.
  Verificación: las unidades compilan.
  Hecho: las cinco compilan en el build del proyecto. Además: `GetTempPath`/`GetTempFileName` de Win32 → `SysUtils.GetTempFileName` en `frmSongInfoDlg` (6 sitios); en `frmExportWavDlg`, `Trunc(Abs(cardinal))` era ambiguo en FPC y el `Abs` llegaba tarde (tras convertir a `Cardinal`): ahora `Abs(StrToIntDef(...)) * 44100`. La ruta `'\z80.tab'` que se pasa a `ReadASMTableFile` se ignora (lee el recurso), así que no hace falta tocarla.
- [ ] `frmSTMainWnd.pas`: inicializar/cerrar el audio en `FormCreate/FormDestroy`, quitar `timeBeginPeriod` y similares, convertir los manejadores `WM_*` en eventos del hilo, ayuda con `OpenDocument`.
  Verificación: `lazbuild Beepola.lpi` termina sin errores y genera el binario.
  Hecho el código: todas las unidades del proyecto compilan con `lazbuild`, pero el enlazado falla igual que en 1.3 (`malformed method list atom … cocoawsextctrls.o`). Cambios: `AudioInit`/`AudioDone` (si el audio no abre se avisa y se sigue con el reloj de reserva, en vez de salir dejando `SpecEmu` a `nil`), sin `timeBeginPeriod`, `WM_*` → métodos sin parámetros asignados a los eventos de `ZXPlay` en los 3 sitios, ayuda con `OpenDocument(<bundle>/Contents/Resources/help/index.html)` (o la URL si no está), literales `'é'` etc. → `#$E9`… (mismo valor CP1252 que daba Delphi), `GetKeyboardLayout` sustituido por un QWERTY fijo y `{$R BeepolaData.RES}` con el nombre exacto (FPC distingue mayúsculas).
  BLOQUEADA: falta el binario; depende de la solución de enlazado de la tarea 1.3 (FPC 3.2.4).

## 7. Primera ejecución

- [ ] Arrancar la app y corregir los errores de carga de los `.lfm` (propiedades desconocidas, etc.).
  Verificación: `./Beepola` (o `open Beepola.app`) muestra la ventana principal sin excepciones; abrir cada diálogo del menú no lanza errores.
- [ ] Tocar notas con el teclado en el editor de patrones.
  Verificación: suena cada nota y la octava cambia correctamente.
- [ ] Reproducir patrón y canción con cada motor (SFX, TMB, MSD, P1D, P1S, SVG, RMB, PLP).
  Verificación: el audio va a tempo, el resaltado de fila avanza y Stop corta limpio, sin bloqueos.
- [ ] Probar los botones de test de instrumento Phaser1 y de ornamento Savage.
  Verificación: suenan y devuelven el control a la UI.

## 8. Adaptaciones Mac

- [ ] Atajos alternativos: Insert también con Ctrl+I, octava con Ctrl+1…5; en los menús, Ctrl → Cmd bajo `{$IFDEF DARWIN}`.
  Verificación: en un MacBook sin teclado numérico se insertan filas, se cambia de octava y Cmd+S/Cmd+O funcionan.
- [ ] Ajustes visuales: fuentes, alturas de las rejillas, owner-draw de `grdPattern`/`grdSong`, `pbxLoopStart`.
  Verificación: comparación visual con la versión de Windows; ningún texto cortado ni solapado.

## 9. Funcionalidad de ficheros

- [ ] Guardar y abrir un `.bbsong`.
  Verificación: guardar, cerrar, reabrir → contenido idéntico; `cmp` entre dos guardados consecutivos sin cambios.
- [ ] Exportar a WAV.
  Verificación: `afplay` reproduce el fichero; `afinfo` muestra 44100 Hz, mono, 8-bit y la duración esperada.
- [ ] Compilar a `.tap`/`.asm` desde el diálogo Compile con cada motor.
  Verificación: el `.tap` carga y suena en un emulador (p. ej. Fuse); si es posible, `cmp` con la salida de `Beepola.exe` original.
- [ ] Persistencia de opciones y MRU.
  Verificación: cambiar las opciones, abrir 2 canciones, reiniciar la app → las opciones y la lista MRU se conservan.

## 10. Empaquetado

- [ ] `build_macos.sh`: compila, monta `Beepola.app` (`Info.plist`, `Beepola.icns` generado con `sips`/`iconutil`, `help/` en `Resources`) y firma en ad-hoc (`codesign -s -`).
  Verificación: `./build_macos.sh && codesign -v Beepola.app && open Beepola.app`; el menú Ayuda abre la ayuda local.
