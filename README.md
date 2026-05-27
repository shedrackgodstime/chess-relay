# Chess Relay

Chess Relay is a Rust + Iroh + Bevy game project targeting desktop and mobile platforms.

## Linux Setup

On Linux, Bevy depends on several native system libraries that must be installed before `cargo run` will succeed.

For Debian/Ubuntu/Kali-based systems, install:

```bash
sudo apt update
sudo apt install pkg-config libasound2-dev libudev-dev
```

If you see build errors mentioning `alsa`, `libudev`, or `pkg-config`, this is the most likely cause.

## Build and Run

```bash
cargo run
```

## Troubleshooting

- `pkg-config` must be installed and available on your `PATH`.
- If `cargo run` reports missing `alsa.pc` or `libudev.pc`, the development package was not found.
- Make sure `PKG_CONFIG_PATH` is set if you installed libraries in a non-standard location.

Example for custom install paths:

```bash
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
cargo run
```
