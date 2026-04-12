# Changelog

## [0.2.4](https://github.com/joshrotenberg/tinfoil/compare/v0.2.3...v0.2.4) (2026-04-12)


### Features

* auto-detect OTP/Zig versions, stricter Homebrew validation ([#37](https://github.com/joshrotenberg/tinfoil/issues/37)) ([69c7c9e](https://github.com/joshrotenberg/tinfoil/commit/69c7c9eaa76fb65201d36cd24f5c207eaf9f0844))
* tag/version validation, test helpers, darwin runner fix ([#34](https://github.com/joshrotenberg/tinfoil/issues/34)) ([b9c2428](https://github.com/joshrotenberg/tinfoil/commit/b9c242887dd6d47616efd1a9f9027242bc3d4ab4)), closes [#15](https://github.com/joshrotenberg/tinfoil/issues/15)

## [0.2.3](https://github.com/joshrotenberg/tinfoil/compare/v0.2.2...v0.2.3) (2026-04-10)


### Features

* **publish:** handle existing releases with --replace flag ([#9](https://github.com/joshrotenberg/tinfoil/issues/9)) ([df5354f](https://github.com/joshrotenberg/tinfoil/commit/df5354feffdb23e122163851c75841c2a8782d92))


### Bug Fixes

* **archive:** emit executable binaries in release tarballs ([#7](https://github.com/joshrotenberg/tinfoil/issues/7)) ([2c1d1be](https://github.com/joshrotenberg/tinfoil/commit/2c1d1bef88d8ee0e537a507d0bc0c49a6cb2b8e1))
* **config:** validate archive_name, archive_format, and homebrew tap ([#10](https://github.com/joshrotenberg/tinfoil/issues/10)) ([bcd448b](https://github.com/joshrotenberg/tinfoil/commit/bcd448bbbaed9f023f63a1caf18b18652059c495))
* **publish:** add retry and upload timeout to the GitHub API client ([#11](https://github.com/joshrotenberg/tinfoil/issues/11)) ([98ccb2a](https://github.com/joshrotenberg/tinfoil/commit/98ccb2aa6c4148adf996c0d1a4481ffe3b8000fd))

## [0.2.2](https://github.com/joshrotenberg/tinfoil/compare/v0.2.1...v0.2.2) (2026-04-10)


### Features

* 0.3.0 defaults and release workflow cache ([#5](https://github.com/joshrotenberg/tinfoil/issues/5)) ([4a97f00](https://github.com/joshrotenberg/tinfoil/commit/4a97f00b68fb073573a9f1456f7cd90fc21c101f))

## [0.2.1](https://github.com/joshrotenberg/tinfoil/compare/v0.2.0...v0.2.1) (2026-04-10)


### Bug Fixes

* **publish:** start :req before making HTTP requests ([#3](https://github.com/joshrotenberg/tinfoil/issues/3)) ([0730b3c](https://github.com/joshrotenberg/tinfoil/commit/0730b3cb86f51457821fc6be0bccce04626d01d6))
