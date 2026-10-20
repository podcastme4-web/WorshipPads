
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:audio_session/audio_session.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    // Modern Edge-to-Edge display configuration for Android 15 (SDK 35)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  
  // Keep screen awake while app is open
  WakelockPlus.enable();

  // Preserve native splash until initial frame / assets are ready
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize mobile ads safely (skip on desktop platforms)
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint("Ads initialization error: $e");
    }
  }

  // Configure iOS/Android audio session so sound pads don't stay muted
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);
  } catch (e) {
    debugPrint("Audio session configuration error: $e");
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final soloudTempDir = Directory('${tempDir.path}/SoLoudLoader-Temp-Files');
    if (!await soloudTempDir.exists()) {
      await soloudTempDir.create(recursive: true);
    }
  } catch (e) {
    debugPrint("Temp directory creation error: $e");
  }

  try {
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
      debugPrint("SoLoud engine initialized successfully!");
    }
  } catch (e) {
    debugPrint("SoLoud engine initialization error: $e");
  }

  runApp(const WorshipPadsApp());
}

class WorshipPadsApp extends StatelessWidget {
  const WorshipPadsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Worship Pads × Peter Junior's",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        canvasColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF000000),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF000000),
          elevation: 0,
        ),
      ),
      home: const PadPlayerScreen(),
    );
  }
}

class PadPlayerScreen extends StatefulWidget {
  const PadPlayerScreen({super.key});

  @override
  State<PadPlayerScreen> createState() => _PadPlayerScreenState();
}

enum VocalEffect { dry, pop, studio, echo } 

class _PadPlayerScreenState extends State<PadPlayerScreen> {
  bool isDrumMode = false;

  // Worship Pad variables
  String selectedSound = 'synth';
  String selectedScale = 'major';
  String? activeNote;
  bool isLowOctave = false;
  double transitionSeconds = 3.0;
  double masterVolume = 0.8;

  final Map<String, AudioSource> _loadedSources = {};
  SoundHandle? _activeHandle;
  final List<SoundHandle> _fadingHandles = [];

  // Drum Loop & Kit variables
  int selectedLoopIndex = 3; 
  AudioSource? _currentDrumLoopSource;
  SoundHandle? _drumLoopHandle;
  bool isDrumLoopPlaying = false;
  double currentBpm = 70.0;
  final double baseFileBpm = 70.0;

  VocalEffect _selectedVocalEffect = VocalEffect.dry;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool isRecording = false;
  String? lastRecordedFilePath;
  AudioSource? _recordedVoiceSource;
  SoundHandle? _recordedVoiceHandle;
  bool isPlayingVoice = false;

  Future<void> _toggleVoiceRecording() async {
    try {
      if (isRecording) {
        final String? path = await _audioRecorder.stop();
        print("DEBUG: Recorded file path is: $path");

        if (path != null) {
          await Future.delayed(const Duration(milliseconds: 150));

          final file = File(path);
          if (await file.exists() && await file.length() > 0) {
            print("DEBUG: File verified on disk. Size: ${await file.length()} bytes");

            final source = await SoLoud.instance.loadFile(path);
            print("DEBUG: SoLoud loaded source: $source");

            setState(() {
              isRecording = false;
              lastRecordedFilePath = path;
              _recordedVoiceSource = source;
            });
          } else {
            print("DEBUG: Error - File is empty or does not exist!");
            setState(() { isRecording = false; });
          }
        } else {
          setState(() { isRecording = false; });
        }
      } else {
        if (await _audioRecorder.hasPermission()) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/vocal_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
          
          await _audioRecorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              bitRate: 128000,
              sampleRate: 44100,
              numChannels: 1,
            ),
            path: filePath,
          );
          
          setState(() { isRecording = true; });
        }
      }
    } catch (e) {
      debugPrint("Error toggling voice recording: $e");
    }
  }

  Future<void> _playRecordedVoice() async {
    if (_recordedVoiceSource == null) {
      print("DEBUG: Cannot play. Source is null.");
      return;
    }

    try {
      if (isPlayingVoice && _recordedVoiceHandle != null) {
        SoLoud.instance.setPause(_recordedVoiceHandle!, true);
        setState(() {
          isPlayingVoice = false;
        });
        print("DEBUG: Voice playback paused.");
        return;
      }

      if (_recordedVoiceHandle != null && SoLoud.instance.getIsValidVoiceHandle(_recordedVoiceHandle!)) {
        SoLoud.instance.setPause(_recordedVoiceHandle!, false);
        setState(() {
          isPlayingVoice = true;
        });
        print("DEBUG: Voice playback resumed.");
        return;
      }

      print("DEBUG: Starting fresh playback process...");
      _recordedVoiceHandle = SoLoud.instance.play(_recordedVoiceSource!);
      print("DEBUG: Playback started successfully with handle: $_recordedVoiceHandle");

      setState(() {
        isPlayingVoice = true;
      });
    } catch (e, stackTrace) {
      print("DEBUG ERROR: Failed to play recorded voice: $e");
      print(stackTrace);
      setState(() {
        isPlayingVoice = false;
      });
    }
  }

  Future<void> _shareRecordedVoice() async {
    if (lastRecordedFilePath == null) {
      print("DEBUG: No recorded file available to share.");
      return;
    }

    try {
      await Share.shareXFiles(
        [XFile(lastRecordedFilePath!)],
        text: 'Check out my recording from Worship Pads!',
      );
    } catch (e) {
      print("DEBUG ERROR: Failed to share recording: $e");
    }
  }

  Widget buildVoiceRecorderBar() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _toggleVoiceRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: isRecording ? Colors.redAccent : Colors.blueGrey,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: Icon(isRecording ? Icons.stop : Icons.mic, size: 18),
              label: Text(isRecording ? 'STOP' : 'REC', style: const TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<VocalEffect>(
              isExpanded: true,
              value: _selectedVocalEffect,
              dropdownColor: const Color(0xFF1F2937),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: VocalEffect.values.map((effect) {
                return DropdownMenuItem(
                  value: effect,
                  child: Text(effect.name.toUpperCase(), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() => _selectedVocalEffect = newValue);
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (lastRecordedFilePath == null || isRecording) ? null : _shareRecordedVoice,
              style: ElevatedButton.styleFrom(
                backgroundColor: lastRecordedFilePath == null ? Colors.grey : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('SHARE', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (_recordedVoiceSource == null || isRecording) ? null : _playRecordedVoice,
              style: ElevatedButton.styleFrom(
                backgroundColor: _recordedVoiceSource == null ? Colors.grey : Colors.blueGrey,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: Icon(isPlayingVoice ? Icons.pause : Icons.play_arrow, size: 18),
              label: Text(isPlayingVoice ? 'PAUSE' : 'PLAY', style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  final Map<int, AudioSource> _loopSources = {};
  final Map<String, AudioSource> _drumKitSources = {};
  String? activeDrumPad;

  // AdMob Ad Variables
  AppOpenAd? _appOpenAd;
  
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdLoading = false;
  final String _interstitialAdUnitId = 'ca-app-pub-6960153006904624/1296608019';
  final String _appOpenAdUnitId = 'ca-app-pub-6960153006904624/5782219337';

  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  final String _bannerAdUnitId = 'ca-app-pub-6960153006904624/5478472161';

  final List<Map<String, String>> notes = const [
    {'label': 'C', 'key': 'c'},
    {'label': 'C#', 'key': 'cs'},
    {'label': 'D', 'key': 'd'},
    {'label': 'D#', 'key': 'ds'},
    {'label': 'E', 'key': 'e'},
    {'label': 'F', 'key': 'f'},
    {'label': 'F#', 'key': 'fs'},
    {'label': 'G', 'key': 'g'},
    {'label': 'G#', 'key': 'gs'},
    {'label': 'A', 'key': 'a'},
    {'label': 'A#', 'key': 'as'},
    {'label': 'B', 'key': 'b'},
  ];

  final List<Map<String, String>> drumKitPads = const [
    {'label': 'CRASH', 'key': '1', 'sub': 'Cymbal'},
    {'label': 'RIDE', 'key': '2', 'sub': 'Cymbal'},
    {'label': 'HI-HAT', 'key': '3', 'sub': 'Closed'},
    {'label': 'SNARE', 'key': '4', 'sub': 'Acoustic'},
    {'label': 'CLAP', 'key': '5', 'sub': 'Layer'},
    {'label': 'RIM', 'key': '6', 'sub': 'Click'},
    {'label': 'KICK 1', 'key': '7', 'sub': 'Heavy'},
    {'label': 'KICK 2', 'key': '8', 'sub': 'Punch'},
    {'label': 'TOM', 'key': '9', 'sub': 'Floor'},
  ];

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      _preloadCurrentSet(); // Load primary worship pads immediately so app is instantly ready
      _loadBannerAd();
      
      // Defer heavy asset loading and ad initialization slightly so startup feels lightning fast
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
          _loadAndShowAppOpenAd();
          _preloadInterstitialAd();
          _preloadDrumKit();
          _preloadAllLoops();
        }
      });
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isBannerAdLoaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Banner ad failed to load: $error');
        },
      ),
    )..load();
  }

  Future<void> _preloadAllLoops() async {
    if (!SoLoud.instance.isInitialized) return;
    for (int i = 1; i <= 19; i++) {
      try {
        final src = await SoLoud.instance.loadAsset('assets/audio/drums/loops/$i.wav');
        _loopSources[i] = src;
      } catch (e) {
        debugPrint("Error loading loop $i.wav: $e");
      }
    }
    _currentDrumLoopSource = _loopSources[selectedLoopIndex];
  }

  Future<void> _preloadDrumKit() async {
    if (!SoLoud.instance.isInitialized) return;
    for (var pad in drumKitPads) {
      final key = pad['key']!;
      final path = 'assets/audio/drums/kit/$key.wav';
      try {
        final src = await SoLoud.instance.loadAsset(path);
        _drumKitSources[key] = src;
      } catch (e) {
        debugPrint("Error loading kit sample $path: $e");
      }
    }
  }

  // App Open Ad Startup Logic
  Future<void> _loadAndShowAppOpenAd() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    bool hasInternet = connectivityResults.contains(ConnectivityResult.mobile) || 
                       connectivityResults.contains(ConnectivityResult.wifi) ||
                       connectivityResults.contains(ConnectivityResult.ethernet);
    if (!hasInternet) return;

    AppOpenAd.load(
      adUnitId: _appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _appOpenAd = null;
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _appOpenAd = null;
            },
          );
          _appOpenAd!.show();
        },
        onAdFailedToLoad: (error) {
          debugPrint('App Open ad failed to load: $error');
        },
      ),
    );
  }

  // Pre-load Interstitial Ad in background
  void _preloadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdLoading = false;
          
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              // Automatically pause pads and loops so ad sound doesn't clash
              if (_activeHandle != null && SoLoud.instance.isInitialized) {
                SoLoud.instance.setPause(_activeHandle!, true);
              }
              if (isDrumLoopPlaying && _drumLoopHandle != null && SoLoud.instance.isInitialized) {
                SoLoud.instance.setPause(_drumLoopHandle!, true);
              }
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              // Resume playback smoothly after the ad closes
              if (_activeHandle != null && SoLoud.instance.isInitialized) {
                SoLoud.instance.setPause(_activeHandle!, false);
              }
              if (isDrumLoopPlaying && _drumLoopHandle != null && SoLoud.instance.isInitialized) {
                SoLoud.instance.setPause(_drumLoopHandle!, false);
              }
              // Preload next interstitial ad
              _preloadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _preloadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialAdLoading = false;
          debugPrint('Interstitial failed to load: $error');
        },
      ),
    );
  }

  // Show preloaded Interstitial Ad instantly on transition
  void _showInterstitialOnTransition() {
    if (_interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      debugPrint('Interstitial ad not ready yet.');
      _preloadInterstitialAd();
    }
  }

  Future<void> _preloadCurrentSet() async {
    if (!SoLoud.instance.isInitialized) return;
    for (var src in _loadedSources.values) {
      await SoLoud.instance.disposeSource(src);
    }
    _loadedSources.clear();

    for (var note in notes) {
      final key = note['key']!;
      final assetPath = 'assets/audio/$selectedSound/$selectedScale/$key.wav';
      try {
        final src = await SoLoud.instance.loadAsset(assetPath);
        _loadedSources[key] = src;
      } catch (e) {
        debugPrint("Error preloading $assetPath: $e");
      }
    }
  }

  void _toggleDrumLoop() async {
    if (!SoLoud.instance.isInitialized) return;

    if (isDrumLoopPlaying) {
      if (_drumLoopHandle != null) {
        await SoLoud.instance.stop(_drumLoopHandle!);
      }
      setState(() => isDrumLoopPlaying = false);
    } else {
      if (_currentDrumLoopSource == null) return;
      try {
        final handle = SoLoud.instance.play(_currentDrumLoopSource!, looping: true);
        _drumLoopHandle = handle;
        double speedRatio = currentBpm / baseFileBpm;
        SoLoud.instance.setRelativePlaySpeed(handle, speedRatio);
        setState(() => isDrumLoopPlaying = true);
      } catch (e) {
        debugPrint("Error playing loop: $e");
      }
    }
  }

  void _changeLoop(int newIndex) async {
    bool wasPlaying = isDrumLoopPlaying;
    if (wasPlaying && _drumLoopHandle != null && SoLoud.instance.isInitialized) {
      await SoLoud.instance.stop(_drumLoopHandle!);
      setState(() => isDrumLoopPlaying = false);
    }

    setState(() {
      selectedLoopIndex = newIndex;
      _currentDrumLoopSource = _loopSources[newIndex];
    });

    if (wasPlaying) {
      _toggleDrumLoop();
    }
  }

  void _updateDrumTempo(double newBpm) {
    setState(() => currentBpm = newBpm);
    if (isDrumLoopPlaying && _drumLoopHandle != null && SoLoud.instance.isInitialized) {
      double speedRatio = currentBpm / baseFileBpm;
      SoLoud.instance.setRelativePlaySpeed(_drumLoopHandle!, speedRatio);
    }
  }

  void _handleDrumPadPress(String key) async {
    setState(() => activeDrumPad = key);
    
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => activeDrumPad = null);
    });

    if (!SoLoud.instance.isInitialized) return;
    final src = _drumKitSources[key];
    if (src != null) {
      try {
        SoLoud.instance.play(src, volume: masterVolume);
      } catch (e) {
        debugPrint("Error triggering drum pad $key: $e");
      }
    }
  }

  void _onSoundOrScaleChanged({String? sound, String? scale}) async {
    final handleToStop = _activeHandle;
    _activeHandle = null;

    setState(() {
      activeNote = null;
      if (sound != null) selectedSound = sound;
      if (scale != null) selectedScale = scale;
    });

    if (handleToStop != null && SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.fadeVolume(handleToStop, 0.0, const Duration(milliseconds: 150));
        await Future.delayed(const Duration(milliseconds: 160));
        if (SoLoud.instance.isInitialized) await SoLoud.instance.stop(handleToStop);
      } catch (_) {}
    }
    await _preloadCurrentSet();
  }

  void _toggleOctave() {
    setState(() => isLowOctave = !isLowOctave);
    if (_activeHandle != null && SoLoud.instance.isInitialized) {
      SoLoud.instance.setRelativePlaySpeed(_activeHandle!, isLowOctave ? 0.5 : 1.0);
    }
  }

  void _adjustTransitionTime(double delta) {
    setState(() {
      transitionSeconds = (transitionSeconds + delta).clamp(1.0, 10.0);
    });
  }

  void _handlePadPress(String noteKey) {
    if (activeNote == noteKey) {
      _stopAudioWithFade();
    } else {
      _crossfadeToNewNote(noteKey);
    }
  }

  void _crossfadeToNewNote(String noteKey) async {
    setState(() => activeNote = noteKey);
    if (!SoLoud.instance.isInitialized) return;

    final sourceToPlay = _loadedSources[noteKey];
    if (sourceToPlay == null) return;

    final oldHandle = _activeHandle;
    if (oldHandle != null) {
      _fadingHandles.add(oldHandle);
      final fadeMs = (transitionSeconds * 1000).toInt();
      SoLoud.instance.fadeVolume(oldHandle, 0.0, Duration(milliseconds: fadeMs));

      Future.delayed(Duration(milliseconds: fadeMs), () async {
        try {
          if (SoLoud.instance.isInitialized) await SoLoud.instance.stop(oldHandle);
        } catch (_) {}
        _fadingHandles.remove(oldHandle);
      });
    }

    try {
      final newHandle = SoLoud.instance.play(sourceToPlay, volume: 0.0, looping: true);
      _activeHandle = newHandle;
      SoLoud.instance.setRelativePlaySpeed(newHandle, isLowOctave ? 0.5 : 1.0);
      
      final fadeMs = (transitionSeconds * 1000).toInt();
      SoLoud.instance.fadeVolume(newHandle, masterVolume, Duration(milliseconds: fadeMs));
    } catch (e) {
      debugPrint("Error playing $noteKey: $e");
    }
  }

  void _stopAudioWithFade() async {
    setState(() => activeNote = null);
    final handleToStop = _activeHandle;
    _activeHandle = null;

    if (handleToStop != null && SoLoud.instance.isInitialized) {
      try {
        SoLoud.instance.fadeVolume(handleToStop, 0.0, const Duration(milliseconds: 100));
        Future.delayed(const Duration(milliseconds: 110), () async {
          if (SoLoud.instance.isInitialized) await SoLoud.instance.stop(handleToStop);
        });
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _stopAudioWithFade();
    if (_drumLoopHandle != null && SoLoud.instance.isInitialized) {
      SoLoud.instance.stop(_drumLoopHandle!);
    }
    for (var src in _loadedSources.values) {
      SoLoud.instance.disposeSource(src);
    }
    for (var src in _drumKitSources.values) {
      SoLoud.instance.disposeSource(src);
    }
    for (var src in _loopSources.values) {
      SoLoud.instance.disposeSource(src);
    }
    _appOpenAd?.dispose();
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    if (SoLoud.instance.isInitialized) SoLoud.instance.deinit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 90,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1218),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withAlpha(80),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/icons/iconss1.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'WORSHIP PADS',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: Colors.white),
                ),
                SizedBox(height: 1),
                Text(
                  "× Peter Junior's",
                  style: TextStyle(fontSize: 16, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (activeNote != null && !isDrumMode)
            Padding(
              padding: const EdgeInsets.only(right: 14.0),
              child: Center(
                child: GestureDetector(
                  onTap: _stopAudioWithFade,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.redAccent.withAlpha(100)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.stop, color: Colors.redAccent, size: 16),
                        SizedBox(width: 4),
                        Text('STOP', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0D14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF19202D)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => isDrumMode = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              gradient: !isDrumMode ? const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF0284C7)]) : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'WORSHIP PADS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: !isDrumMode ? Colors.black : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => isDrumMode = true);
                            // Show preloaded interstitial ad instantly on transition
                            _showInterstitialOnTransition();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              gradient: isDrumMode ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFE11D48)]) : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'DRUM KIT & LOOP',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: isDrumMode ? Colors.white : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                if (!isDrumMode) ...[
                  _buildSelectorRow(
                    options: ['synth', 'analog'],
                    selectedOption: selectedSound,
                    activeGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    onSelect: (val) => _onSoundOrScaleChanged(sound: val),
                  ),
                  const SizedBox(height: 8),
                  _buildSelectorRow(
                    options: ['major', 'minor'],
                    selectedOption: selectedScale,
                    activeGradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                    onSelect: (val) => _onSoundOrScaleChanged(scale: val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0D14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF19202D)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('TRANSITION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                  const SizedBox(height: 2),
                                  Text('${transitionSeconds.toInt()}s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF38BDF8))),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildStepButton(icon: Icons.remove, onPressed: transitionSeconds > 1.0 ? () => _adjustTransitionTime(-1) : null),
                                  const SizedBox(width: 8),
                                  _buildStepButton(icon: Icons.add, onPressed: transitionSeconds < 10.0 ? () => _adjustTransitionTime(1) : null),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: GestureDetector(
                          onTap: _toggleOctave,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: isLowOctave ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]) : null,
                              color: isLowOctave ? null : const Color(0xFF0A0D14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isLowOctave ? Colors.white.withAlpha(100) : const Color(0xFF19202D)),
                            ),
                            child: Center(
                              child: Text(
                                '-1 OCTAVE',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isLowOctave ? Colors.black : const Color(0xFFCBD5E1)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0D14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF19202D)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.loop, size: 16, color: Color(0xFFF43F5E)),
                                const SizedBox(width: 8),
                                Text('LOOP: $selectedLoopIndex.wav', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF43F5E))),
                              ],
                            ),
                            GestureDetector(
                              onTap: _toggleDrumLoop,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isDrumLoopPlaying ? Colors.redAccent.withAlpha(40) : const Color(0xFF19202D),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isDrumLoopPlaying ? Colors.redAccent : const Color(0xFF2A3447)),
                                ),
                                child: Text(
                                  isDrumLoopPlaying ? 'STOP LOOP' : 'PLAY LOOP',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDrumLoopPlaying ? Colors.redAccent : Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: 19,
                            itemBuilder: (context, index) {
                              final loopNum = index + 1;
                              final isSelected = selectedLoopIndex == loopNum;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () => _changeLoop(loopNum),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFF43F5E) : const Color(0xFF19202D),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Loop $loopNum',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Tempo:', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                                child: Slider(
                                  value: currentBpm,
                                  min: 50.0,
                                  max: 120.0,
                                  divisions: 70,
                                  activeColor: const Color(0xFFF43F5E),
                                  inactiveColor: const Color(0xFF19202D),
                                  onChanged: _updateDrumTempo,
                                ),
                              ),
                            ),
                            Text('${currentBpm.round()} BPM', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFF43F5E))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                buildVoiceRecorderBar(),

                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0D14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF19202D)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.volume_up, size: 15, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          const Text('MASTER VOLUME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                          const Spacer(),
                          Text('${(masterVolume * 100).round()}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                        child: Slider(
                          value: masterVolume,
                          min: 0.0,
                          max: 1.0,
                          activeColor: const Color(0xFF10B981),
                          inactiveColor: const Color(0xFF19202D),
                          onChanged: (val) {
                            setState(() => masterVolume = val);
                            if (_activeHandle != null && SoLoud.instance.isInitialized) {
                              SoLoud.instance.setVolume(_activeHandle!, masterVolume);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    if (!isDrumMode) {
                      if (index >= notes.length) return const SizedBox.shrink();
                      final note = notes[index];
                      final isPlaying = activeNote == note['key'];

                      return GestureDetector(
                        onTap: () => _handlePadPress(note['key']!),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            gradient: isPlaying
                                ? const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF0284C7)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                : const LinearGradient(colors: [Color(0xFF0A0D14), Color(0xFF05070B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isPlaying ? Colors.white : const Color(0xFF19202D), width: isPlaying ? 2.5 : 1),
                            boxShadow: isPlaying
                                ? [BoxShadow(color: const Color(0xFF38BDF8).withAlpha(160), blurRadius: 22, spreadRadius: 4)]
                                : [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: Center(
                            child: Text(
                              note['label']!,
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isPlaying ? Colors.black : const Color(0xFFE2E8F0)),
                            ),
                          ),
                        ),
                      );
                    } else {
                      if (index >= drumKitPads.length) return const SizedBox.shrink();
                      
                      final pad = drumKitPads[index];
                      final key = pad['key']!;
                      const activeColor = Color(0xFFF43F5E);
                      final isPlaying = activeDrumPad == key;

                      return GestureDetector(
                        onTap: () => _handleDrumPadPress(key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 80),
                          decoration: BoxDecoration(
                            gradient: isPlaying
                                ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFBE123C)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                : const LinearGradient(colors: [Color(0xFF0A0D14), Color(0xFF05070B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isPlaying ? Colors.white : const Color(0xFF19202D), width: isPlaying ? 2.5 : 1),
                            boxShadow: isPlaying
                                ? [BoxShadow(color: activeColor.withAlpha(160), blurRadius: 18, spreadRadius: 3)]
                                : [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                pad['label']!,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isPlaying ? Colors.white : const Color(0xFFE2E8F0)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pad['sub']!,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isPlaying ? Colors.white70 : const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 6),

                if (_isBannerAdLoaded && _bannerAd != null)
                  Container(
                    alignment: Alignment.center,
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF19202D)),
                    ),
                    child: AdWidget(ad: _bannerAd!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepButton({required IconData icon, required VoidCallback? onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: onPressed != null ? const Color(0xFF19202D) : const Color(0xFF05070B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: onPressed != null ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
      ),
    );
  }

  Widget _buildSelectorRow({
    required List<String> options,
    required String selectedOption,
    required List<Color> activeGradient,
    required Function(String) onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF19202D)),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = selectedOption == option;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected ? LinearGradient(colors: activeGradient) : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  option.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: isSelected ? Colors.black : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
