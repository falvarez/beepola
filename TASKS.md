# Tareas: port de Beepola a macOS

Plan completo en [docs/PLAN.md](docs/PLAN.md). Tareas en orden de ejecución; cada una indica cómo verificarla.

## 1. Toolchain

- [x] Instalar FPC con Homebrew (`brew install fpc`).
  Verificación: `fpc -i` muestra la versión y `fpc -iTP` incluye `aarch64`.
- [x] Descargar el código fuente estable de Lazarus en `~/opt/lazarus` y compilar `lazbuild` (`make lazbuild`).
  Verificación: `~/opt/lazarus/lazbuild --version` imprime la versión.
  Hecho: tag `lazarus_4_8`, `make lazbuild LCL_PLATFORM=cocoa`; enlaza sin `-k-ld_classic`.
- [x] Compilar un "hola mundo" LCL/Cocoa de prueba (un form con un botón) en el scratchpad con `lazbuild --ws=cocoa`.
  Verificación: el binario arranca y muestra la ventana. Si el enlazado falla, probar `-k-ld_classic` y anotar el flag necesario en `docs/PLAN.md`.
  Hecho: con FPC 3.2.2 el enlazado fallaba (`malformed method list atom … cocoawsextctrls.o`) y `-k-ld_classic` ya no existe. Se compiló FPC 3.2.4 (`release_3_2_4`) en `~/opt/fpc` (`make all OPT="-XR$SDK -Fl$SDK/usr/lib"`, `make install PREFIX=~/opt/fpc`, `fpc.cfg` en `~/opt/fpc/etc` generado con `samplecfg` + rutas del SDK), se recompiló `lazbuild` con él y `~/.lazarus/environmentoptions.xml` apunta a `~/opt/fpc/bin/fpc`. El hola mundo enlaza sin flags extra y muestra su ventana.

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

- [x] Crear `BeeperAudio.pas` (AudioQueue, 44100 Hz mono 16-bit, ring buffer de unos 6 frames, `AudioInit/AudioDone/AudioWriteFrame/AudioReset`).
  Verificación: un programa de prueba en consola genera 2 s de onda cuadrada a 440 Hz en frames de 882 muestras; se oye limpia y dura unos 2 s (`time`).
  Hecho: la prueba tarda 2,02 s (1,88 s escribiendo + vaciado del ring) y da 0 underruns mientras suena (el único que cuenta es el vaciado final). Dos trampas resueltas: `constref` para el `AudioStreamBasicDescription` (con `cdecl`, `const` pasa el record por valor) y `SetExceptionMask` (CoreAudio dispara excepciones FP que FPC desenmascara por defecto). Confirmado a oído por el usuario: suena limpia.
- [x] `SpecEmu.pas`: quitar `MMSystem`/WaveOut/`GlobalAlloc`; `OutputWave` usa `AudioWriteFrame`; throttle en `Interrupt` basado en el bloqueo del audio, con fallback por `GetTickCount64`/`Sleep`; `CopyMemory` → `Move`.
  Verificación: `fpc -Mdelphi SpecEmu.pas` compila; un programa de prueba carga `sfx_img`, pone una nota y ejecuta 100 interrupciones → se oye la nota durante unos 2 s.
  Hecho: compila contra la LCL (o contra stubs de `Forms`/`Dialogs`/`LCLType` en la prueba de consola, porque la LCL Cocoa no enlaza todavía, ver 1.3). 100 interrupciones: 1,88 s con audio (+0,12 s de vaciado), 0 underruns; sin dispositivo, el reloj de reserva tarda 1,98 s. Renderizada a WAV, la nota suena los 2 s. `ResetWaveBuffers` NO llama a `AudioReset`: se usa al final de cada nota tocada y cortaría su cola (Windows tampoco descartaba el audio en cola). Confirmado a oído por el usuario.

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
- [x] `frmSTMainWnd.pas`: inicializar/cerrar el audio en `FormCreate/FormDestroy`, quitar `timeBeginPeriod` y similares, convertir los manejadores `WM_*` en eventos del hilo, ayuda con `OpenDocument`.
  Verificación: `lazbuild Beepola.lpi` termina sin errores y genera el binario.
  Hecho. Cambios: `AudioInit`/`AudioDone` (si el audio no abre se avisa y se sigue con el reloj de reserva, en vez de salir dejando `SpecEmu` a `nil`), sin `timeBeginPeriod`, `WM_*` → métodos sin parámetros asignados a los eventos de `ZXPlay` en los 3 sitios, ayuda con `OpenDocument(<bundle>/Contents/Resources/help/index.html)` (o la URL si no está), literales `'é'` etc. → `#$E9`… (mismo valor CP1252 que daba Delphi), `GetKeyboardLayout` sustituido por un QWERTY fijo y `{$R BeepolaData.RES}` con el nombre exacto (FPC distingue mayúsculas).
  Con FPC 3.2.4, `lazbuild Beepola.lpi` termina sin errores y genera `Beepola` (arm64, 17 MB) y `Beepola.app`.

## 7. Primera ejecución

- [x] Arrancar la app y corregir los errores de carga de los `.lfm` (propiedades desconocidas, etc.).
  Verificación: `./Beepola` (o `open Beepola.app`) muestra la ventana principal sin excepciones; abrir cada diálogo del menú no lanza errores.
  Hecho sin cambios de código: `./Beepola` abre la ventana principal (875×560) sin diálogos de error, con los 15 formularios creados al arrancar. Un programa de prueba (scratchpad `formtest`) crea los mismos formularios y hace `Show`/`Hide` de los 14 diálogos (se ejecutan sus `OnShow`, incluido el ensamblado de todos los motores en SongInfo y la música del About): 0 excepciones. Falta la revisión visual (sección 8).
- [x] Tocar notas con el teclado en el editor de patrones.
  Verificación: suena cada nota y la octava cambia correctamente.
  Hecho: el usuario lo probó a mano en la app y suenan las notas. La prueba automática con pulsaciones de System Events necesita permiso de Accesibilidad para `osascript` (pendiente). Al arrancar, el foco queda en `txtOctave` (primer control en el orden de tabulación, probablemente igual que en la VCL). Las teclas de octava del teclado numérico se tratan en 8.1.
- [ ] Reproducir patrón y canción con cada motor (SFX, TMB, MSD, P1D, P1S, SVG, RMB, PLP).
  Verificación: el audio va a tempo, el resaltado de fila avanza y Stop corta limpio, sin bloqueos.
  Programa de prueba `keytest -play` (3 s de patrón y 3 s de canción por motor): SFX, TMB, MSD, P1D, P1S y SVG suenan, el resaltado avanza (16 filas en el patrón, 16–24 cambios de fila en la canción), sin underruns durante la reproducción, y Stop vuelve en unos 220 ms (el `Sleep(210)` original de `TPlayerThread`), con la fila restaurada. Corregido por el camino: el diálogo de error del emulador se abría desde el hilo de reproducción y Cocoa abortaba la app (ahora va por `TThread.Synchronize`), y `LoadFile`/`SaveFile` liberaban un stream sin inicializar si el fichero no se podía abrir.
  BLOQUEADA (limitación del código original, no del port): PLP no tiene imagen ni cargador en el emulador de la 1.06.02 (suena silencio) y RMB usa instrucciones Z80 que el emulador no implementa (`BIT/RES/SET` sobre `(IX+d)`, `RES b,(HL)`, `AND B`…). Hay que decidir si se completa el emulador Z80.
- [x] Probar los botones de test de instrumento Phaser1 y de ornamento Savage.
  Verificación: suenan y devuelven el control a la UI.
  Hecho: el test de Phaser1 vuelve en 0,7 s y el de ornamento Savage en 0,5 s, los dos con sonido y sin excepciones (`keytest -play`); el usuario también los probó a mano.

## 8. Adaptaciones Mac

- [x] Atajos alternativos: Insert también con Ctrl+I, octava con Ctrl+1…5; en los menús, Ctrl → Cmd bajo `{$IFDEF DARWIN}`.
  Verificación: en un MacBook sin teclado numérico se insertan filas, se cambia de octava y Cmd+S/Cmd+O funcionan.
  Distribuciones AZERTY/QWERTZ: ver «Más adelante».
  Hecho el código (bajo `{$IFDEF DARWIN}`): Ctrl+I → `VK_INSERT`; Ctrl+1…5 fijan la octava (sin enfocar `udnOctave`), y el `KeyPress` que pueda seguir se descarta hasta el `KeyUp` para que no entre como nota; Retroceso actúa como Supr en las rejillas (la tecla «delete» del Mac); en los menús Ctrl → Cmd, más Cmd+N/Cmd+O, que el original no tenía (Cmd+Shift+S ya es «Shrink ×2»). Comprobado llamando a los manejadores (`keytest -check`): atajos Meta+…, octava, inserción de fila y teclado numérico original sin excepciones. Probado por el usuario con el teclado del MacBook: funciona (compuso `sokoban.bbsong`).
- [x] Ajustes visuales: fuentes, alturas de las rejillas, owner-draw de `grdPattern`/`grdSong`, `pbxLoopStart`.
  Verificación: comparación visual con la versión de Windows; ningún texto cortado ni solapado.
  Hecho: no hay capturas del original para comparar, así que la referencia son los `.lfm`; revisadas con capturas la ventana principal (SFX, Phaser1, Savage) y los 14 diálogos. Tahoma 11 px existe en macOS, el form principal mide exactamente lo diseñado (972×594) y las rejillas owner-draw y `pbxLoopStart` se ven bien. Problemas corregidos con `MacLayout.FixVCLLayout`, que se aplica a todos los forms desde el `.lpr`: en Cocoa los hijos de un `TGroupBox` se recortaban (el área útil empieza 22 px más abajo y pierde 26 px, y la VCL ya desplazaba los hijos por su título), y las etiquetas sueltas junto a casillas sin texto quedaban tapadas por la casilla, más ancha. La ventana Keyboard Layout se ensancha a la línea más larga (ya no cabía en Windows) y muestra las alternativas Mac de Ins, Supr y octava.

## 9. Funcionalidad de ficheros

- [x] Guardar y abrir un `.bbsong`.
  Verificación: guardar, cerrar, reabrir → contenido idéntico; `cmp` entre dos guardados consecutivos sin cambios.
  Hecho: `sokoban.bbsong` (compuesta y guardada por el usuario en la app de macOS, que la reabrió desde la MRU) cargada y guardada de nuevo es idéntica byte a byte, y un segundo ciclo carga/guardado también (`cmp`). Un fichero inexistente da `EFOpenError` (aviso), no un cuelgue.
- [x] Exportar a WAV.
  Verificación: `afplay` reproduce el fichero; `afinfo` muestra 44100 Hz, mono, 8-bit y la duración esperada.
  Hecho: con los mismos pasos que `TExportWavDlg.cmdOKClick` (programa de consola `exportwav`), `sokoban.bbsong` hasta el final de la canción da 706 frames = 14,12 s y en modo fijo 10 s exactos; `afinfo`: WAVE, 1 canal, 44100 Hz, PCM 8 bits sin signo; `afplay` lo reproduce entero. Corregido un error del original: el tamaño RIFF de la cabecera se escribía 4 bytes corto (`datos + 32` en vez de `+ 36`). El diálogo en sí (selector de fichero, botón Abort) no se ha probado de forma automática.
- [ ] Compilar a `.tap`/`.asm` desde el diálogo Compile con cada motor.
  Verificación: el `.tap` carga y suena en un emulador (p. ej. Fuse); si es posible, `cmp` con la salida de `Beepola.exe` original.
  Hecho salvo la escucha: `keytest -compile` ejecuta el `cmdOKClick` real del diálogo (con un `TSaveDialog` falso y cerrando el aviso final con OK) sobre `sokoban.bbsong` con los 7 motores, en `.tap` con cargador BASIC y en `.asm`: sin errores. Cada `.tap` tiene bloques y checksums XOR correctos (cargador «Beepola» con `CLEAR 59999 / LOAD ""CODE / RANDOMIZE USR 60000`, más el bloque «Sokoban» en 60000), y el código del `.tap` es idéntico byte a byte al que da `pasmo` ensamblando el `.asm` generado, lo que valida el ensamblador portado. PENDIENTE: cargar un `.tap` en un emulador (Retro Virtual Machine) y oírlo; la comparación con el `.exe` 1.08.01 daría diferencias de versión (el REM del cargador, por ejemplo).
- [x] Persistencia de opciones y MRU.
  Verificación: cambiar las opciones, abrir 2 canciones, reiniciar la app → las opciones y la lista MRU se conservan.
  Hecho: dos ejecuciones de `keytest` con `XDG_CONFIG_HOME` en el scratchpad. En la primera se activan las dos opciones con el `cmdOKClick` real de Options y se abren dos canciones con `mnuFileOpenClick` (diálogo de apertura falso). En la segunda, `RegSettings` y el diálogo muestran las opciones activas, la rejilla numera en hexadecimal («0A») y el menú File lista `dos` y `uno` en ese orden. El `beepola.ini` del usuario también conserva la MRU entre sesiones.

## 10. Empaquetado

- [x] `build_macos.sh`: compila, monta `Beepola.app` (`Info.plist`, `Beepola.icns` generado con `sips`/`iconutil`, `help/` en `Resources`) y firma en ad-hoc (`codesign -s -`).
  Verificación: `./build_macos.sh && codesign -v Beepola.app && open Beepola.app`; el menú Ayuda abre la ayuda local.
  Hecho salvo el clic en Ayuda: el script compila con `lazbuild` (ruta en `LAZBUILD`), monta `Beepola.app` desde cero con el ejecutable copiado (no enlazado), `Info.plist` (`local.beepola.Beepola`, 1.06.02, macOS 11+), `PkgInfo`, `Beepola.icns` (con `sips`/`iconutil`; el `.ico` llega a 48×48, así que los tamaños grandes salen escalados) y `help/` (la ayuda de la 1.08.01, ahora en el repo; si faltara, avisa y el menú abre la ayuda en línea), y firma ad-hoc. `codesign -v`: válida; `open Beepola.app` arranca. Ojo: no hay que poner `NSPrincipalClass` en el plist, porque la LCL usa su propia subclase de `NSApplication` y la app aborta al arrancar. Se quitó `UseAppBundle` del `.lpi` para que `lazbuild` no cree su propio bundle con un enlace simbólico. La ruta de la ayuda (`<exe>/../Resources/help/index.html`) se comprobó con un bundle de prueba lanzado con `open`. Comprobado por el usuario: Help → Online Help Contents abre la ayuda local en el navegador.

## Más adelante

- [ ] Distribución de teclado en macOS: `GetKeyboardLayout` devuelve siempre QWERTY; leer la distribución activa (`TISCopyCurrentKeyboardLayoutInputSource`) y devolver los identificadores AZERTY (`$040C040C`) y QWERTZ (`$04070407`…) que espera `KeyToNoteVal`/`IsValidNoteKey`.
  Verificación: con la distribución francesa o alemana activa, las teclas de nota siguen la disposición del piano de esa distribución.
- [ ] Completar el emulador Z80 de `SpecEmu.pas` para que RMB suene: faltan instrucciones sin prefijo (p. ej. `AND B`), buena parte de `CB`/`ED` y de las indexadas (`DD`/`FD`, `DD CB`). Las ya escritas para `BIT/RES/SET` están en `specemu-full.diff` del scratchpad de la sesión del 2026-11-13. PLP necesita además una imagen de reproductor (`plp_img`) y su cargador, que este código no tiene.
  Verificación: `keytest -play 6` (o reproducir con RMB en la app) suena sin «emulation error»; comparar la salida WAV con la del `.exe` 1.08.01 si es posible.
