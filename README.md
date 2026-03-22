# AudioSampler

Menu bar app for macOS that records system audio. Pick an app or capture everything.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- Record system audio from any app or all apps at once
- Source picker lists running audio-capable applications
- Saves recordings as WAV to `~/Music/AudioSampler/`
- Live recording timer in the menu bar
- Keyboard shortcut: Cmd+R to start/stop
- Lives in the menu bar -- no dock icon
- Zero dependencies, native Swift + ScreenCaptureKit

## Install

### Download

Grab the latest `.app.zip` from [Releases](../../releases), unzip, and drag to `/Applications`.

### Build from source

```bash
git clone https://github.com/lukeloxton/AudioSampler.git
cd AudioSampler
bash build.sh
```

## Permissions

On first launch, macOS will ask for **Screen Recording** permission (required by ScreenCaptureKit to capture audio). Grant it in System Settings > Privacy & Security > Screen Recording.

## License

MIT
