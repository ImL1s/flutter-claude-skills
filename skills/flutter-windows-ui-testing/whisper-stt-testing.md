---
description: Test Whisper STT offline voice recognition accuracy using TTS-generated audio and whisper-cli.exe on Windows
---

# Whisper STT Testing Skill

Test offline Whisper speech recognition on Windows using TTS-generated audio files and `whisper-cli.exe`.

## Prerequisites

- **whisper-cli.exe**: Located at `build/windows/x64/runner/Release/whisper/whisper-cli.exe` (bundled with app build)
- **Whisper models**: Located at `%APPDATA%/com.example.yourapp/models/whisper/`
  - `ggml-tiny.bin` (74 MB) — fastest, lowest accuracy
  - `ggml-small.bin` (465 MB) — good balance for Chinese
- **Windows SAPI TTS**: Built-in, no install needed. `Microsoft Hanhan Desktop` (zh-TW) for Chinese.

## Step 1: Generate Test Audio

Use Windows SAPI TTS to generate WAV files (16kHz, 16-bit, mono — what Whisper expects):

```powershell
Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

# Select Chinese voice
$zhVoice = $synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like "zh*" } | Select-Object -First 1
$synth.SelectVoice($zhVoice.VoiceInfo.Name)

$synth.Rate = 0  # -10 to 10, 0 = normal
$wavPath = "$env:TEMP\whisper_test.wav"
$synth.SetOutputToWaveFile($wavPath, (New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
    16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)))

$synth.Speak("你要測試的中文句子")
$synth.SetOutputToNull()
$synth.Dispose()
```

### Recommended Test Scenarios

Generate separate WAV files for each:

| # | Scenario | Content | Why |
|---|----------|---------|-----|
| 1 | Long paragraph | 3+ sentences, varied vocabulary | Tests sustained accuracy |
| 2 | Technical terms | 設定、伺服器、軟體、應用程式 | Tests domain vocabulary |
| 3 | Short command | Single sentence, fast speech (`Rate=2`) | Common voice keyboard usage |
| 4 | Numbers/dates | 年月日、數字 | Tests numeric handling |
| 5 | English | Full English sentence | Ensures no false conversion |

## Step 2: Run whisper-cli

### Basic transcription

```powershell
$cli = "build\windows\x64\runner\Release\whisper\whisper-cli.exe"
$model = "%APPDATA%\com.example.yourapp\models\whisper\ggml-small.bin"

& $cli -m $model -f $wavPath -l zh --no-timestamps -np 2>$null | Out-File "result.txt" -Encoding utf8
```

### With Traditional Chinese prompt (recommended for zh-TW)

```powershell
& $cli -m $model -f $wavPath -l zh --no-timestamps -np --prompt "以下是繁體中文的句子。" 2>$null | Out-File "result_prompt.txt" -Encoding utf8
```

### Compare modes

Always test BOTH with and without `--prompt` to measure prompt effectiveness.

## Step 3: Interpret Results

### What to check

1. **Character accuracy**: Compare output text against expected input
2. **繁/簡 consistency**: With `--prompt`, ALL Chinese should be Traditional
3. **Vocabulary correctness**: 鼠标→滑鼠, 软件→軟體 (after OpenCC S2TWp)
4. **Number handling**: Whisper may convert Chinese numbers to Arabic (二零二六→2026)
5. **No hallucination**: Short/silent audio shouldn't produce random text

### Known Whisper behaviors

- ggml-small: Responds well to `--prompt`, outputs mostly Traditional with prompt
- ggml-tiny: Often ignores `--prompt`, outputs Simplified regardless
- Short sentences: May output Traditional even WITHOUT prompt (model-dependent)
- Numbers: Whisper converts spoken Chinese numbers to Arabic digits (expected)

## Verified Test Results (March 2026)

| Test | No Prompt | With Prompt | OpenCC Needed? |
|------|-----------|-------------|----------------|
| Long paragraph | 全簡體 | **全繁體** ✅ | Safety net only |
| Tech terms | 全簡體 | **全繁體** ✅ | Safety net only |
| Short command | 繁體 (!) | 繁體 | Not needed |
| Numbers/dates | 主要簡體 | **全繁體** ✅ | Safety net only |
| English | Correct | N/A | N/A |

### Actual output examples

```
Long paragraph (no prompt):
今天我想跟大家分享一个重要的消息。我们的团队已经完成了新产品的开发...

Long paragraph (with prompt):
今天我想跟大家分享一個重要的消息。我們的團隊已經完成了新產品的開發...
```

## Limitations of TTS Testing

| Aspect | TTS | Real Human Speech |
|--------|-----|-------------------|
| Pronunciation | Perfect | Varies (accent, dialect) |
| Background noise | None | Office, street, etc. |
| Speaking speed | Fixed | Variable |
| Language mixing | N/A | Common ("那個 meeting 的 schedule") |
| Hesitation/filler | None | "呃", "那個", pauses |

### How to test with real speech

1. **Record yourself**: Use `record` package or system recorder → 16kHz WAV
2. **Mozilla Common Voice zh-TW**: Download from commonvoice.mozilla.org (2.93 GB)
3. **Build and use the app**: `fvm flutter build windows` → speak through the UI

## Integration with the App

The app's Whisper STT pipeline:

```
User speaks → PCM 16kHz → WAV file → whisper-cli.exe
  → (--prompt '以下是繁體中文的句子。')  ← for zh-TW/zh-HK only
  → Raw transcription
  → ChineseTextConverter.autoConvert()  ← OpenCC S2TWp post-processing
  → Final Traditional Chinese text
```

Files involved:
- `lib/features/dictation/data/whisper_cli_stt_service.dart` (Windows/Linux)
- `lib/features/dictation/data/whisper_stt_service.dart` (iOS/Android FFI)
- `lib/core/utils/chinese_text_converter.dart` (OpenCC wrapper)
