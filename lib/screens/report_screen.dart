import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ia_service.dart';
import '../services/arcore_depth_frame.dart';
import '../services/arcore_depth_service.dart';
import '../services/cloudinary_service.dart';
import '../services/location_validation_service.dart';
import '../services/supabase_service.dart';
import '../models/bache_model.dart';
import 'register_success_screen.dart';

enum _PhotoFailureAction { retry, saveWithoutPhoto, cancel }

typedef RegistrationSuccessCallback = Future<void> Function(Bache bache);

class ReportScreenController {
  Future<bool> Function()? _confirmLeave;

  Future<bool> confirmLeave() async => await _confirmLeave?.call() ?? true;

  void _attach(Future<bool> Function() callback) {
    _confirmLeave = callback;
  }

  void _detach(Future<bool> Function() callback) {
    _confirmLeave = null;
  }
}

class _OptionalPhotoResult {
  const _OptionalPhotoResult({required this.url}) : cancelled = false;

  const _OptionalPhotoResult.cancelled()
      : url = '',
        cancelled = true;

  final String url;
  final bool cancelled;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    this.controller,
    this.onRegistrationSuccess,
    this.onResourcesReleased,
  });

  final ReportScreenController? controller;
  final RegistrationSuccessCallback? onRegistrationSuccess;
  final VoidCallback? onResourcesReleased;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with WidgetsBindingObserver {
  final IAService _iaService = IAService();
  final ArCoreDepthService _arCoreDepthService = ArCoreDepthService();
  final SupabaseService _supabaseService = SupabaseService();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];

  bool _camaraLista = false;
  bool _analizando = false;
  bool _guardando = false;
  bool _procesandoFrame = false;
  bool _deteccionPausada = false;
  bool _streamActivo = false;
  bool _cerrandoPantalla = false;
  bool _appEnPausa = false;
  bool _modeloListo = false;
  bool _usarArCoreDepth = false;
  bool _vistaArCoreLista = false;
  bool _loopArCoreActivo = false;
  int _generacionArCore = 0;
  ArCoreDepthFrame? _ultimoFrameArCore;

  Future<void>? _transicionStream;
  Future<void> _transicionLifecycle = Future.value();
  int _generacionCamara = 0;

  Map<String, dynamic>? _resultado;
  File? _fotoEvidencia;
  CloudinaryUploadResult? _fotoSubidaPendiente;
  Future<CloudinaryUploadResult>? _subidaFotoEnCurso;
  DateTime? _fechaRegistroPendiente;
  Position? _posicion;
  String _mensaje = '';

  DateTime? _ultimoAnalisis;
  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_confirmarSalida);
    WidgetsBinding.instance.addObserver(this);
    _inicializarTodo();
  }

  Future<bool> _confirmarSalida() async {
    if (_guardando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Espera a que termine el registro.')),
      );
      return false;
    }
    if (_resultado == null &&
        _fotoEvidencia == null &&
        _fotoSubidaPendiente == null) {
      return true;
    }

    final hasRemotePhoto = _fotoSubidaPendiente != null;
    final abandonar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title:
            Text(hasRemotePhoto ? 'Registro pendiente' : 'Descartar reporte'),
        content: Text(
          hasRemotePhoto
              ? 'La foto ya fue cargada, pero el bache aún no se guardó. '
                  'Si abandonas, podría quedar sin asociar.'
              : 'Existe una detección pendiente. Si abandonas Reportar, se '
                  'descartará esta sesión.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar reportando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonar'),
          ),
        ],
      ),
    );
    return abandonar == true;
  }

  Future<void> _inicializarTodo() async {
    try {
      await _iaService.cargarModelo();
      _modeloListo = true;
    } catch (e) {
      debugPrint('Error cargando modelo: $e');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = 'No se pudo cargar el modelo de detección.';
        });
      }
    }

    if (!mounted || _cerrandoPantalla) return;
    final arCore = await _arCoreDepthService.probe();
    if (!mounted || _cerrandoPantalla) return;
    debugPrint(
      'ARCORE_AVAILABLE=${arCore.arCoreAvailable} '
      'DEPTH_AUTOMATIC_SUPPORTED=${arCore.automaticDepthSupported} '
      'RAW_DEPTH_SUPPORTED=${arCore.rawDepthSupported} '
      'state=${arCore.availability} reason=${arCore.reason}',
    );
    debugPrint(
      'SPOTHOLE_AR arcoreAvailable=${arCore.arCoreAvailable} '
      'automaticDepth=${arCore.automaticDepthSupported} '
      'rawDepth=${arCore.rawDepthSupported}',
    );
    if (arCore.canUseAutomaticDepth) {
      final permisoCamara = await Permission.camera.request();
      if (!mounted || _cerrandoPantalla) return;
      if (permisoCamara.isGranted) {
        debugPrint('SPOTHOLE_AR backend=arcore');
        setState(() {
          _usarArCoreDepth = true;
          _camaraLista = true;
          _mensaje = 'Iniciando medición automática...';
        });
      } else {
        debugPrint('SPOTHOLE_AR backend=none reason=camera_permission');
        setState(() {
          _mensaje = permisoCamara.isPermanentlyDenied
              ? 'Permiso de cámara denegado. Habilítalo en los ajustes.'
              : 'Se necesita el permiso de cámara para detectar baches.';
        });
      }
    } else {
      debugPrint(
        'SPOTHOLE_AR backend=camera_controller '
        'reason=${arCore.reason ?? 'depth_unsupported'}',
      );
      await _iniciarCamara();
    }
    if (!mounted || _cerrandoPantalla) return;
    unawaited(_obtenerUbicacion());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appEnPausa = false;
      _encolarTransicionLifecycle();
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _appEnPausa = true;
      _encolarTransicionLifecycle();
    }
  }

  void _encolarTransicionLifecycle() {
    _transicionLifecycle = _transicionLifecycle.then((_) async {
      if (_cerrandoPantalla) return;
      if (_appEnPausa) {
        await _pausarPorLifecycle();
      } else {
        await _reanudarTrasLifecycle();
      }
    }).catchError((Object error) {
      debugPrint('Error cambiando estado de cámara: $error');
    });
  }

  Future<void> _pausarPorLifecycle() async {
    _generacionCamara++;
    if (_usarArCoreDepth) {
      _generacionArCore++;
      _loopArCoreActivo = false;
      try {
        await _arCoreDepthService.pauseDepthCamera();
      } catch (error) {
        debugPrint('Error pausando ARCore: $error');
      }
      return;
    }
    await _liberarCamara();
  }

  Future<void> _reanudarTrasLifecycle() async {
    if (!mounted || _cerrandoPantalla || _appEnPausa) return;

    if (_usarArCoreDepth) {
      try {
        await _arCoreDepthService.resumeDepthCamera();
        _iniciarLoopArCore();
      } catch (error) {
        debugPrint('Error reanudando ARCore: $error');
        await _cambiarAFallbackCamara();
      }
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _iniciarCamara();
    }
  }

  Future<void> _iniciarCamara() async {
    if (_cerrandoPantalla || _appEnPausa) return;

    final generacion = ++_generacionCamara;
    CameraController? controller;

    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _mensaje = 'No se encontró cámara disponible.';
          });
        }
        return;
      }

      controller = CameraController(
        _cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted ||
          _cerrandoPantalla ||
          _appEnPausa ||
          generacion != _generacionCamara) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      setState(() {
        _camaraLista = true;
        if (_modeloListo) {
          _mensaje = 'Apunta al bache para detectar.';
        }
      });

      if (_modeloListo && !_deteccionPausada) {
        await _iniciarStreamDeteccion();
      }
    } on CameraException catch (e) {
      await controller?.dispose();
      debugPrint('Error iniciando cámara (${e.code}): ${e.description}');

      if (!mounted || _cerrandoPantalla) return;

      final permisoDenegado = e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted';
      setState(() {
        _mensaje = permisoDenegado
            ? 'Permiso de cámara denegado. Habilítalo en los ajustes.'
            : 'Error iniciando cámara: ${e.description ?? e.code}';
      });
    } catch (e) {
      await controller?.dispose();
      debugPrint('Error iniciando cámara: $e');

      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = 'Error iniciando cámara: $e';
        });
      }
    }
  }

  Future<void> _iniciarStreamDeteccion() async {
    final transicionAnterior = _transicionStream;
    if (transicionAnterior != null) {
      await transicionAnterior;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages || _streamActivo) return;
    if (_cerrandoPantalla || _appEnPausa || !_modeloListo) return;

    final operacion = controller.startImageStream(_procesarFrame);
    _transicionStream = operacion;
    try {
      await operacion;
      if (_cameraController == controller &&
          !_cerrandoPantalla &&
          !_appEnPausa) {
        _streamActivo = true;
      }
    } catch (e) {
      debugPrint('Error iniciando stream de cámara: $e');
    } finally {
      if (identical(_transicionStream, operacion)) {
        _transicionStream = null;
      }
    }
  }

  Future<void> _detenerStreamDeteccion() async {
    final transicionAnterior = _transicionStream;
    if (transicionAnterior != null) {
      try {
        await transicionAnterior;
      } catch (_) {}
    }

    final controller = _cameraController;
    _streamActivo = false;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) return;

    final operacion = controller.stopImageStream();
    _transicionStream = operacion;
    try {
      await operacion;
    } catch (e) {
      debugPrint('Error deteniendo stream de cámara: $e');
    } finally {
      if (identical(_transicionStream, operacion)) {
        _transicionStream = null;
      }
    }
  }

  Future<void> _liberarCamara() async {
    final controller = _cameraController;
    _cameraController = null;
    _streamActivo = false;

    if (mounted && !_cerrandoPantalla) {
      setState(() => _camaraLista = false);
    } else {
      _camaraLista = false;
    }

    if (controller == null) return;

    final transicion = _transicionStream;
    if (transicion != null) {
      try {
        await transicion;
      } catch (_) {}
    }

    try {
      if (controller.value.isInitialized &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Error deteniendo cámara al liberarla: $e');
    }

    await controller.dispose();
  }

  Future<Position?> _obtenerUbicacion() async {
    try {
      final servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) {
        _posicion = null;
        if (mounted && !_cerrandoPantalla) {
          setState(() {
            _mensaje = 'Activa la ubicación y vuelve a intentar el registro.';
          });
        }
        return null;
      }

      LocationPermission permiso = await Geolocator.checkPermission();

      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        _posicion = null;
        if (mounted && !_cerrandoPantalla) {
          setState(() {
            _mensaje = permiso == LocationPermission.deniedForever
                ? 'Habilita el permiso de ubicación en los ajustes y vuelve a intentar.'
                : 'Se necesita el permiso de ubicación para registrar el bache.';
          });
        }
        return null;
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final validation = LocationValidationService.validate(
        posicion,
        now: DateTime.now(),
      );

      if (!validation.isValid) {
        _posicion = null;
        debugPrint('Posición GPS rechazada: ${validation.failure}');
        if (mounted && !_cerrandoPantalla) {
          setState(() {
            _mensaje = switch (validation.failure) {
              LocationValidationFailure.insufficientAccuracy =>
                'La señal GPS no tiene precisión suficiente. Ve a un lugar despejado y reintenta.',
              LocationValidationFailure.mocked =>
                'No se puede registrar con una ubicación simulada.',
              _ =>
                'No se obtuvo una ubicación GPS válida. Vuelve a intentarlo.',
            };
          });
        }
        return null;
      }

      if (mounted && !_cerrandoPantalla) {
        setState(() => _posicion = posicion);
      }
      return posicion;
    } on TimeoutException catch (e) {
      _posicion = null;
      debugPrint('Timeout obteniendo GPS: $e');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje =
              'La ubicación tardó demasiado. Ve a un lugar despejado y reintenta.';
        });
      }
      return null;
    } catch (e) {
      _posicion = null;
      debugPrint('Error GPS: $e');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = 'No se pudo obtener la ubicación. Vuelve a intentarlo.';
        });
      }
      return null;
    }
  }

  Future<void> _eliminarFotoEvidenciaLocal() async {
    try {
      if (_fotoEvidencia != null && await _fotoEvidencia!.exists()) {
        await _fotoEvidencia!.delete();
      }
    } catch (e) {
      debugPrint('Error eliminando foto evidencia local: $e');
    } finally {
      _fotoEvidencia = null;
    }
  }

  Future<void> _capturarFotoEvidencia() async {
    if (_usarArCoreDepth) {
      await _capturarFotoEvidenciaArCore();
      return;
    }
    final controller = _cameraController;
    if (controller == null) return;
    if (!controller.value.isInitialized) return;
    if (_cerrandoPantalla) return;

    try {
      if (_streamActivo) {
        await _detenerStreamDeteccion();
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (_cerrandoPantalla ||
          _appEnPausa ||
          _cameraController != controller ||
          !controller.value.isInitialized) {
        return;
      }

      final XFile foto = await controller.takePicture();
      _fotoEvidencia = File(foto.path);

      debugPrint('Foto de evidencia capturada: ${_fotoEvidencia!.path}');
    } catch (e) {
      debugPrint('Error capturando foto de evidencia: $e');
      _fotoEvidencia = null;
    }
  }

  Future<void> _capturarFotoEvidenciaArCore() async {
    if (_cerrandoPantalla) return;
    try {
      final frame =
          _ultimoFrameArCore ?? await _arCoreDepthService.acquireFrame();
      if (frame == null || _cerrandoPantalla) return;
      final bytes = await Isolate.run(() {
        final image = IAService.convertirFrameArCoreAImagen(frame);
        return img.encodeJpg(image, quality: 90);
      });
      if (_cerrandoPantalla) return;
      final separator = Platform.pathSeparator;
      final file = File(
        '${Directory.systemTemp.path}${separator}spothole_'
        '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (_cerrandoPantalla) {
        await file.delete();
        return;
      }
      _fotoEvidencia = file;
      debugPrint('Foto ARCore temporal capturada: ${file.path}');
    } catch (error) {
      debugPrint('Error capturando foto ARCore: $error');
      _fotoEvidencia = null;
    }
  }

  void _onVistaArCoreCreada(int _) {
    if (_cerrandoPantalla || !_usarArCoreDepth) return;
    _vistaArCoreLista = true;
    unawaited(_reanudarVistaArCore());
  }

  Future<void> _reanudarVistaArCore() async {
    try {
      await _arCoreDepthService.resumeDepthCamera();
      if (!mounted || _cerrandoPantalla || _appEnPausa) return;
      setState(() => _mensaje = 'Apunta al bache para detectar.');
      _iniciarLoopArCore();
    } catch (error) {
      debugPrint('No se pudo iniciar la sesión ARCore: $error');
      await _cambiarAFallbackCamara();
    }
  }

  void _iniciarLoopArCore() {
    if (_loopArCoreActivo ||
        !_vistaArCoreLista ||
        !_usarArCoreDepth ||
        _appEnPausa ||
        _cerrandoPantalla ||
        !_modeloListo) {
      return;
    }
    _loopArCoreActivo = true;
    final generacion = ++_generacionArCore;
    unawaited(_ejecutarLoopArCore(generacion));
  }

  Future<void> _ejecutarLoopArCore(int generacion) async {
    try {
      while (mounted &&
          !_cerrandoPantalla &&
          !_appEnPausa &&
          !_deteccionPausada &&
          _usarArCoreDepth &&
          generacion == _generacionArCore) {
        if (!_guardando && !_procesandoFrame) {
          final frameAcceptedAtUs = developer.Timeline.now;
          final frame = await _arCoreDepthService.acquireFrame();
          if (frame != null && mounted && generacion == _generacionArCore) {
            _ultimoFrameArCore = frame;
            await _procesarFrameArCore(frame, frameAcceptedAtUs);
          }
        }
        if (generacion != _generacionArCore) break;
        await Future<void>.delayed(const Duration(milliseconds: 2500));
      }
    } on PlatformException catch (error) {
      debugPrint('Error de sesión ARCore (${error.code}): ${error.message}');
      if (mounted && !_cerrandoPantalla) await _cambiarAFallbackCamara();
    } catch (error) {
      debugPrint('Error procesando ARCore: $error');
      if (mounted && !_cerrandoPantalla) await _cambiarAFallbackCamara();
    } finally {
      if (generacion == _generacionArCore) _loopArCoreActivo = false;
    }
  }

  Future<void> _procesarFrameArCore(
    ArCoreDepthFrame frame,
    int frameAcceptedAtUs,
  ) async {
    _procesandoFrame = true;
    if (mounted) setState(() => _analizando = true);
    try {
      final resultado = await _iaService.detectarDesdeArCoreFrame(
        frame,
        frameAcceptedAtUs: frameAcceptedAtUs,
      );
      if (!mounted || _cerrandoPantalla) return;
      if (resultado == null) {
        setState(() {
          _resultado = null;
          _mensaje = 'Buscando bache...';
          _analizando = false;
        });
        return;
      }

      _deteccionPausada = true;
      _generacionArCore++;
      await _capturarFotoEvidencia();
      if (!mounted || _cerrandoPantalla) return;
      setState(() {
        _resultado = resultado;
        _mensaje = _fotoEvidencia != null
            ? '✅ Bache detectado. Foto de evidencia lista.'
            : '✅ Bache detectado. Puedes registrarlo sin foto.';
        _analizando = false;
      });
    } catch (error) {
      debugPrint('Error analizando frame ARCore: $error');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _analizando = false;
          _mensaje = 'Error analizando frame.';
        });
      }
    } finally {
      _procesandoFrame = false;
    }
  }

  Future<void> _cambiarAFallbackCamara() async {
    if (!_usarArCoreDepth || _cerrandoPantalla) return;
    _generacionArCore++;
    _loopArCoreActivo = false;
    _vistaArCoreLista = false;
    _ultimoFrameArCore = null;
    try {
      await _arCoreDepthService.disposeDepthCamera();
    } catch (error) {
      debugPrint('Error cerrando ARCore para fallback: $error');
    }
    if (!mounted || _cerrandoPantalla) return;
    setState(() {
      _usarArCoreDepth = false;
      _camaraLista = false;
      _mensaje = 'Depth no disponible. Iniciando detección normal...';
    });
    debugPrint('SPOTHOLE_AR backend=camera_controller reason=arcore_failure');
    await _iniciarCamara();
  }

  Future<void> _procesarFrame(CameraImage image) async {
    final frameAcceptedAtUs = developer.Timeline.now;
    if (_procesandoFrame) return;
    if (_deteccionPausada) return;
    if (_guardando) return;
    if (_cerrandoPantalla) return;
    if (_cameraController == null) return;
    if (!_cameraController!.value.isInitialized) return;

    final ahora = DateTime.now();

    if (_ultimoAnalisis != null &&
        ahora.difference(_ultimoAnalisis!).inMilliseconds < 2500) {
      return;
    }

    _ultimoAnalisis = ahora;
    _procesandoFrame = true;

    if (mounted) {
      setState(() {
        _analizando = true;
      });
    }

    try {
      final controller = _cameraController!;
      final rotationDegrees = IAService.calcularRotacionFrame(
        sensorOrientation: controller.description.sensorOrientation,
        deviceOrientation: controller.value.deviceOrientation,
        lensDirection: controller.description.lensDirection,
      );
      final resultado = await _iaService.detectarDesdeFrame(
        image,
        rotationDegrees: rotationDegrees,
        frameAcceptedAtUs: frameAcceptedAtUs,
      );

      if (!mounted || _cerrandoPantalla) return;

      if (resultado != null) {
        _deteccionPausada = true;

        await _detenerStreamDeteccion();
        await _capturarFotoEvidencia();

        if (!mounted || _cerrandoPantalla) return;

        setState(() {
          _resultado = resultado;
          _mensaje = _fotoEvidencia != null
              ? '✅ Bache detectado. Foto de evidencia lista.'
              : '✅ Bache detectado. Puedes registrarlo sin foto.';
          _analizando = false;
        });
      } else {
        setState(() {
          _resultado = null;
          _mensaje = 'Buscando bache...';
          _analizando = false;
        });
      }
    } catch (e) {
      debugPrint('Error procesando frame: $e');

      if (mounted) {
        setState(() {
          _analizando = false;
          _mensaje = 'Error analizando frame.';
        });
      }
    } finally {
      _procesandoFrame = false;
    }
  }

  Future<_OptionalPhotoResult> _subirFotoEvidenciaOpcional() async {
    final fotoSubida = _fotoSubidaPendiente;
    if (fotoSubida != null) {
      return _OptionalPhotoResult(url: fotoSubida.secureUrl);
    }

    if (_fotoEvidencia == null) {
      return const _OptionalPhotoResult(url: '');
    }

    final deseaGuardarFoto = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Foto de evidencia'),
          content: const Text(
            'La app capturó una foto automáticamente cuando detectó el bache. '
            '¿Deseas guardarla como evidencia?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, guardar sin foto'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sí, guardar foto'),
            ),
          ],
        );
      },
    );

    if (!mounted || _cerrandoPantalla) {
      await _eliminarFotoEvidenciaLocal();
      return const _OptionalPhotoResult.cancelled();
    }

    if (deseaGuardarFoto != true) {
      await _eliminarFotoEvidenciaLocal();
      return const _OptionalPhotoResult(url: '');
    }

    while (mounted && !_cerrandoPantalla) {
      final evidencia = _fotoEvidencia;
      if (evidencia == null) {
        return const _OptionalPhotoResult.cancelled();
      }

      try {
        final operacion = _cloudinaryService.subirFoto(evidencia);
        _subidaFotoEnCurso = operacion;
        final foto = await operacion;
        _fotoSubidaPendiente = foto;

        await _eliminarFotoEvidenciaLocal();
        return _OptionalPhotoResult(url: foto.secureUrl);
      } on CloudinaryUploadException catch (e) {
        debugPrint('Fallo controlado subiendo evidencia: $e');
        if (!mounted || _cerrandoPantalla) {
          await _eliminarFotoEvidenciaLocal();
          return const _OptionalPhotoResult.cancelled();
        }

        final action = await _mostrarOpcionesFalloFoto(e);
        if (!mounted || _cerrandoPantalla) {
          await _eliminarFotoEvidenciaLocal();
          return const _OptionalPhotoResult.cancelled();
        }

        switch (action) {
          case _PhotoFailureAction.retry:
            continue;
          case _PhotoFailureAction.saveWithoutPhoto:
            await _eliminarFotoEvidenciaLocal();
            return const _OptionalPhotoResult(url: '');
          case _PhotoFailureAction.cancel:
            await _eliminarFotoEvidenciaLocal();
            return const _OptionalPhotoResult.cancelled();
        }
      } finally {
        _subidaFotoEnCurso = null;
      }
    }

    await _eliminarFotoEvidenciaLocal();
    return const _OptionalPhotoResult.cancelled();
  }

  Future<_PhotoFailureAction> _mostrarOpcionesFalloFoto(
    CloudinaryUploadException error,
  ) async {
    final motivo = switch (error.failure) {
      CloudinaryUploadFailure.timeout =>
        'La carga tardó demasiado y no pudo confirmarse.',
      CloudinaryUploadFailure.network =>
        'No se pudo conectar con el servicio de fotografías.',
      CloudinaryUploadFailure.rejected =>
        'El servicio de fotografías rechazó la carga.',
      CloudinaryUploadFailure.invalidResponse =>
        'El servicio no devolvió una fotografía válida.',
      CloudinaryUploadFailure.missingFile =>
        'La fotografía temporal ya no está disponible.',
    };

    return await showDialog<_PhotoFailureAction>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('No se pudo guardar la foto'),
            content: Text(
              '$motivo Puedes reintentar, registrar el bache sin foto o cancelar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PhotoFailureAction.cancel,
                ),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PhotoFailureAction.saveWithoutPhoto,
                ),
                child: const Text('Guardar sin foto'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PhotoFailureAction.retry,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ) ??
        _PhotoFailureAction.cancel;
  }

  String _mensajeFalloSupabase(String base) {
    if (_fotoSubidaPendiente == null) return base;
    return '$base La foto ya cargada se reutilizará al reintentar.';
  }

  Future<void> _guardarBache() async {
    if (_guardando) return;

    if (_resultado == null) {
      setState(() {
        _mensaje = 'Primero debes detectar un bache.';
      });
      return;
    }

    final resultadoRegistro = Map<String, dynamic>.from(_resultado!);

    setState(() {
      _guardando = true;
      _analizando = false;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        setState(() {
          _mensaje = 'Tu sesión no es válida. Inicia sesión nuevamente.';
        });
        return;
      }

      final userResponse =
          await auth.getUser().timeout(const Duration(seconds: 15));
      if (!mounted || _cerrandoPantalla) return;
      final usuarioEmail = userResponse.user?.email?.trim();
      if (usuarioEmail == null || usuarioEmail.isEmpty) {
        setState(() {
          _mensaje =
              'La cuenta autenticada no tiene un correo válido. Inicia sesión nuevamente.';
        });
        return;
      }

      final posicionRegistro = await _obtenerUbicacion();
      if (posicionRegistro == null || !mounted || _cerrandoPantalla) return;

      final fechaRegistro = _fechaRegistroPendiente ??= DateTime.now().toUtc();
      await _detenerStreamDeteccion();

      final foto = await _subirFotoEvidenciaOpcional();

      if (!mounted || _cerrandoPantalla) return;
      if (foto.cancelled) {
        _fechaRegistroPendiente = null;
        setState(() {
          _mensaje = 'Registro cancelado. No se guardaron datos.';
        });
        return;
      }

      final bache = Bache(
        latitud: posicionRegistro.latitude,
        longitud: posicionRegistro.longitude,
        fotoUrl: foto.url,
        forma: resultadoRegistro['forma'],
        anchoPx: resultadoRegistro['anchoPx'],
        altoPx: resultadoRegistro['altoPx'],
        anchoCm: resultadoRegistro['anchoCm'],
        altoCm: resultadoRegistro['altoCm'],
        areaCm2: resultadoRegistro['areaCm2'],
        alturaCaptura: resultadoRegistro['alturaMetros'],
        metodoMedicion: resultadoRegistro['metodoMedicion'],
        severidad: resultadoRegistro['severidad'],
        fecha: fechaRegistro,
        confianza: resultadoRegistro['confianza'],
        usuarioEmail: usuarioEmail,
      );

      final bacheGuardado = await _supabaseService.guardarBache(bache);
      debugPrint(
        'Registro confirmado por Supabase; ID válido: '
        '${bacheGuardado.id?.isNotEmpty == true}',
      );

      if (!mounted || _cerrandoPantalla) return;

      _resultado = null;
      _fotoSubidaPendiente = null;
      _fechaRegistroPendiente = null;
      _deteccionPausada = true;
      await _eliminarFotoEvidenciaLocal();

      if (!mounted || _cerrandoPantalla) return;
      final onRegistrationSuccess = widget.onRegistrationSuccess;
      if (onRegistrationSuccess != null) {
        await onRegistrationSuccess(bacheGuardado);
      } else {
        unawaited(
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RegisterSuccessScreen(bache: bacheGuardado),
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      debugPrint('Sesión rechazada al registrar: ${e.runtimeType}');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = 'Tu sesión expiró. Inicia sesión nuevamente.';
        });
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout registrando bache: $e');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = _mensajeFalloSupabase(
            'La operación tardó demasiado. Comprueba tu conexión y reintenta.',
          );
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Supabase rechazó el registro: ${e.code} ${e.message}');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = _mensajeFalloSupabase(
            'No se pudo guardar el registro. Comprueba tu sesión y reintenta.',
          );
        });
      }
    } on SupabaseInsertException catch (e) {
      debugPrint('Respuesta inválida al guardar bache: $e');
      if (mounted && !_cerrandoPantalla) {
        setState(() {
          _mensaje = _mensajeFalloSupabase(
            'No se pudo confirmar el registro. Comprueba tu conexión antes de reintentar.',
          );
        });
      }
    } catch (e) {
      debugPrint('Error guardando bache: $e');
      if (!mounted || _cerrandoPantalla) return;
      setState(() {
        _mensaje = _mensajeFalloSupabase(
          'No se pudo completar el registro. Comprueba tu conexión y reintenta.',
        );
      });
    } finally {
      if (mounted && !_cerrandoPantalla) {
        setState(() => _guardando = false);
      } else {
        _guardando = false;
      }
    }
  }

  Future<void> _reanudarDeteccion() async {
    if (_guardando) return;
    if (_cerrandoPantalla) return;

    if (_fotoSubidaPendiente != null) {
      final abandonar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Registro pendiente'),
          content: const Text(
            'La foto ya fue cargada, pero el bache aún no se guardó. '
            'Reintenta el registro para vincularla. Si abandonas, la foto '
            'podría quedar sin asociar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver al registro'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abandonar'),
            ),
          ],
        ),
      );
      if (!mounted || _cerrandoPantalla || abandonar != true) return;
    }

    await _eliminarFotoEvidenciaLocal();
    if (_fotoSubidaPendiente != null) {
      debugPrint(
        'Se abandonó un registro con una foto remota aún no vinculada.',
      );
    }

    if (!mounted) return;

    setState(() {
      _resultado = null;
      _fotoSubidaPendiente = null;
      _fechaRegistroPendiente = null;
      _mensaje = 'Buscando bache...';
      _deteccionPausada = false;
      _analizando = false;
      _ultimoAnalisis = null;
    });

    if (_usarArCoreDepth) {
      _iniciarLoopArCore();
    } else {
      await _iniciarStreamDeteccion();
    }
  }

  Color _colorSeveridad(String severidad) {
    switch (severidad) {
      case 'Leve':
        return Colors.green;
      case 'Moderado':
        return Colors.orange;
      case 'Severo':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _cerrandoPantalla = true;
    _generacionCamara++;
    widget.controller?._detach(_confirmarSalida);
    WidgetsBinding.instance.removeObserver(this);
    final onResourcesReleased = widget.onResourcesReleased;
    unawaited(_liberarRecursos(onResourcesReleased));

    super.dispose();
  }

  Future<void> _liberarRecursos(VoidCallback? onResourcesReleased) async {
    try {
      try {
        await _transicionLifecycle;
      } catch (_) {}
      await _liberarCamara();
      _generacionArCore++;
      try {
        await _arCoreDepthService.disposeDepthCamera();
      } catch (error) {
        debugPrint('Error liberando ARCore: $error');
      }
      final subidaFoto = _subidaFotoEnCurso;
      if (subidaFoto != null) {
        try {
          await subidaFoto;
        } catch (_) {}
      }
      await _eliminarFotoEvidenciaLocal();
      if (_fotoSubidaPendiente != null) {
        debugPrint(
          'La pantalla se cerró con una foto remota aún no vinculada.',
        );
      }
      _cloudinaryService.dispose();
      _iaService.dispose();
    } finally {
      onResourcesReleased?.call();
    }
  }

  Widget _buildCamaraViva() {
    if (!_camaraLista || (!_usarArCoreDepth && _cameraController == null)) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    return Stack(
      children: [
        SizedBox.expand(
          child: _usarArCoreDepth
              ? AndroidView(
                  viewType: 'spothole/arcore_depth_view',
                  onPlatformViewCreated: _onVistaArCoreCreada,
                )
              : CameraPreview(_cameraController!),
        ),

        // Mira central
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: _resultado != null ? Colors.green : Colors.orange,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _resultado != null ? 'Bache detectado' : 'Apunta al bache',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Estado GPS
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on,
                  color: _posicion != null ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _posicion != null ? 'GPS listo' : 'Sin GPS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Estado de análisis
        Positioned(
          top: 70,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (_analizando && _resultado == null) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.orange,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  Icon(
                    _resultado != null ? Icons.check_circle : Icons.search,
                    color: _resultado != null ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _mensaje.isNotEmpty ? _mensaje : 'Buscando bache...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_resultado != null) _buildPanelResultado(),

        _buildBotonesInferiores(),
      ],
    );
  }

  Widget _buildPanelResultado() {
    final validated = _resultado!['metodoMedicion'] == Bache.metodoAruco;
    final automatic = _resultado!['metodoMedicion'] == Bache.metodoArCoreDepth;
    return Positioned(
      bottom: 145,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _colorSeveridad(_resultado!['severidad']),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🤖 Resultado IA',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _fila(
              Icons.straighten,
              'Bounding box: '
              '${_resultado!['anchoPx'].toStringAsFixed(1)} × '
              '${_resultado!['altoPx'].toStringAsFixed(1)} px',
              textColor: Colors.white,
            ),
            if (validated) ...[
              _fila(
                Icons.verified_outlined,
                'Medición con referencia métrica',
                textColor: Colors.lightGreenAccent,
              ),
              _fila(
                Icons.grid_4x4,
                'Referencia ArUco ID ${_resultado!['marcadorId']}: '
                '${_resultado!['marcadorAnchoCm']} × '
                '${_resultado!['marcadorAltoCm']} cm',
                textColor: Colors.lightGreenAccent,
              ),
              _fila(
                Icons.straighten,
                'Ancho: ${_resultado!['anchoCm']} cm',
                textColor: Colors.white,
              ),
              _fila(
                Icons.height,
                'Alto: ${_resultado!['altoCm']} cm',
                textColor: Colors.white,
              ),
              _fila(
                Icons.crop_square,
                'Área estimada del rectángulo envolvente: '
                '${_resultado!['areaCm2']} cm²',
                textColor: Colors.white,
              ),
            ] else if (automatic) ...[
              _fila(
                Icons.auto_awesome,
                'Medición automática estimada mediante ARCore Depth',
                textColor: Colors.lightBlueAccent,
              ),
              _fila(
                Icons.straighten,
                'Ancho aproximado: ${_resultado!['anchoCm']} cm',
                textColor: Colors.white,
              ),
              _fila(
                Icons.height,
                'Alto aproximado: ${_resultado!['altoCm']} cm',
                textColor: Colors.white,
              ),
              _fila(
                Icons.crop_square,
                'Área aproximada del rectángulo envolvente: '
                '${_resultado!['areaCm2']} cm²',
                textColor: Colors.white,
              ),
              _fila(
                Icons.info_outline,
                'Los valores son aproximados y deben validarse experimentalmente.',
                textColor: Colors.amber,
              ),
            ] else
              _fila(
                Icons.info_outline,
                'Medición automática no disponible para esta captura',
                textColor: Colors.amber,
              ),
            if (validated)
              _fila(
                Icons.science_outlined,
                'Válida solo si marcador y bache están en el mismo plano',
                textColor: Colors.amber,
              ),
            _fila(
              Icons.circle_outlined,
              'Forma: ${_resultado!['forma']}',
              textColor: Colors.white,
            ),
            _fila(
              Icons.percent,
              'Confianza: ${(_resultado!['confianza'] * 100).toStringAsFixed(1)}%',
              textColor: Colors.white,
            ),
            if (_fotoEvidencia != null)
              _fila(
                Icons.photo_camera,
                'Foto de evidencia lista',
                textColor: Colors.white,
              ),
            Row(
              children: [
                Icon(
                  Icons.warning,
                  color: _colorSeveridad(_resultado!['severidad']),
                ),
                const SizedBox(width: 8),
                Text(
                  'Severidad: ${_resultado!['severidad']}',
                  style: TextStyle(
                    color: _colorSeveridad(_resultado!['severidad']),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesInferiores() {
    return Positioned(
      bottom: 35,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_resultado != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _guardando ? null : _guardarBache,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _guardando ? 'Registrando...' : 'Registrar Bache',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          if (_resultado != null) const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _guardando ? null : _reanudarDeteccion,
              icon: const Icon(Icons.refresh),
              label: Text(
                _resultado != null ? 'Seguir detectando' : 'Reiniciar búsqueda',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(
    IconData icono,
    String texto, {
    Color textColor = Colors.black,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icono,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar Bache'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: _buildCamaraViva(),
    );
  }
}
