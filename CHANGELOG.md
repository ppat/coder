# Changelog



## [1.1.1](https://github.com/ppat/coder/compare/v1.1.0...v1.1.1) (2024-06-24)

### 🐛 Enhancements + Bug Fixes

* fix issue where node, terraform and golang sdk were not available ([#42](https://github.com/ppat/coder/issues/42)) ([1bac177](https://github.com/ppat/coder/commit/1bac177f3f2279f232adf2237bf19f8a8b23980f))

## [1.1.0](https://github.com/ppat/coder/compare/v1.0.1...v1.1.0) (2024-06-24)

### ✨ Features

* add minio-cli to coder image ([#39](https://github.com/ppat/coder/issues/39)) ([73e138b](https://github.com/ppat/coder/commit/73e138b8d499b1c5e3e328a994237b92b0a355e7))
* multi-arch builds for coder workspace images ([#40](https://github.com/ppat/coder/issues/40)) ([4c0ef3f](https://github.com/ppat/coder/commit/4c0ef3f329c2b0dafca432d8ca27abf434fc58be))

### 🐛 Enhancements + Bug Fixes

* fix workspace image build for arm64 ([#41](https://github.com/ppat/coder/issues/41)) ([492c303](https://github.com/ppat/coder/commit/492c3033272437faaaa40ef40372a77083e619e9))

### 📌 Dependencies

* **deps:** pin dependencies ([#37](https://github.com/ppat/coder/issues/37)) ([a7b112c](https://github.com/ppat/coder/commit/a7b112c246ac62b5089ad068100d41a7dfa52aaf))
* **deps:** update ghcr.io/coder/coder docker tag to v2.12.2 ([#30](https://github.com/ppat/coder/issues/30)) ([aeb4fb7](https://github.com/ppat/coder/commit/aeb4fb772a7a21f75bbe11a2a5d203297c8486dc))
* **deps:** update github-action dependencies (major) ([#38](https://github.com/ppat/coder/issues/38)) ([9b89b84](https://github.com/ppat/coder/commit/9b89b844eb8226fe14a322103e110df290da4507))

## [1.0.1](https://github.com/ppat/coder/compare/v1.0.0...v1.0.1) (2024-06-22)

### 🐛 Enhancements + Bug Fixes

* remove debug env variable as it results in extraneous output from kubectl ([#31](https://github.com/ppat/coder/issues/31)) ([5e5605a](https://github.com/ppat/coder/commit/5e5605a37abb536f0dbf4d7ef7427703e8abab15))
* **deps:** update dependency renovate to v37.406.2 ([#27](https://github.com/ppat/coder/issues/27)) ([854f87f](https://github.com/ppat/coder/commit/854f87f6a5024d4b53584c4940b94bcc040f8ed7))
* **deps:** update npm major dependencies (major) ([#33](https://github.com/ppat/coder/issues/33)) ([bad6f50](https://github.com/ppat/coder/commit/bad6f500d8e002d92e9b23c5556f145345054d3f))

### ⚙️ Other

* add release notes link during template publish ([#16](https://github.com/ppat/coder/issues/16)) ([b4c444b](https://github.com/ppat/coder/commit/b4c444b9e80ef3591f4e18aecce65df8deccd6d0))
* gate action-lint and renovate-lint linting steps to only run if their corresponding files changed ([#32](https://github.com/ppat/coder/issues/32)) ([b5621fc](https://github.com/ppat/coder/commit/b5621fc615b25864de23d2fc7b88caffd1b6c13d))
* test updates to semantic release configuration or versions ([#17](https://github.com/ppat/coder/issues/17)) ([f3d9a0a](https://github.com/ppat/coder/commit/f3d9a0af42fac5ac9cb92002984f105f0e144ffa))


### 📌 Dependencies

* **deps:** pin dependencies ([#21](https://github.com/ppat/coder/issues/21)) ([52460ac](https://github.com/ppat/coder/commit/52460ac862bcc16d3bfa2e23e072db62f6ab24a0))
* **deps:** update dependency ansible-core to v2.16.7 ([#25](https://github.com/ppat/coder/issues/25)) ([169afc3](https://github.com/ppat/coder/commit/169afc3ecd6c39e1f098273e5bfe1fb0252229e9))
* **deps:** update dependency ansible-core to v2.17.0 ([#28](https://github.com/ppat/coder/issues/28)) ([1b5dfff](https://github.com/ppat/coder/commit/1b5dfffea415ae963ec0b218bd08bcd1d968bf00))
* **deps:** update dependency community.docker to v3.10.4 ([#18](https://github.com/ppat/coder/issues/18)) ([693a067](https://github.com/ppat/coder/commit/693a067166a0bcc854d3034451581de2818978f0))
* **deps:** update dependency community.general to v8.6.2 ([#20](https://github.com/ppat/coder/issues/20)) ([9bf12d2](https://github.com/ppat/coder/commit/9bf12d22ef26f31f4040fd45764cb78538b4cdb0))
* **deps:** update dependency kubernetes/kubernetes to v1.30.2 ([#26](https://github.com/ppat/coder/issues/26)) ([d34c1e5](https://github.com/ppat/coder/commit/d34c1e5e7f8d467a8103d2b66659d6212cd9e0fd))
* **deps:** update dependency node to v20.15.0 ([#29](https://github.com/ppat/coder/issues/29)) ([48b308d](https://github.com/ppat/coder/commit/48b308d7ca624c6f49c884cd819efb27a77dd36d))
* **deps:** update galaxy-collection major dependencies (major) ([#23](https://github.com/ppat/coder/issues/23)) ([5ec3c6b](https://github.com/ppat/coder/commit/5ec3c6b708baf3de591cd03816905707f831d430))
* **deps:** update github-release non-major dependencies ([#10](https://github.com/ppat/coder/issues/10)) ([2896cfa](https://github.com/ppat/coder/commit/2896cfab7859061f346e9bc1ccf6d3e1e65faa8e))
* **deps:** update github-release non-major dependencies ([#19](https://github.com/ppat/coder/issues/19)) ([9107163](https://github.com/ppat/coder/commit/9107163f15bc419a3f807cd0a93142f223b3c151))
* **deps:** update npm major dependencies (major) ([#24](https://github.com/ppat/coder/issues/24)) ([b17a66a](https://github.com/ppat/coder/commit/b17a66a36efdf6df30dbac2b82b9320af438fea3))
* **deps:** update python non-major dependencies ([#22](https://github.com/ppat/coder/issues/22)) ([697f789](https://github.com/ppat/coder/commit/697f78942a06a6c259b084e185da04288921ff31))



## 1.0.0 (2024-06-15)


### ✨ Features

* coder workspace image for homelab workspaces ([#1](https://github.com/ppat/coder/issues/1)) ([6238914](https://github.com/ppat/coder/commit/6238914b3bf4bf21233b117c6844234e92b1584b))
* coder workspace template for homelab-workspaces ([#6](https://github.com/ppat/coder/issues/6)) ([d7c8f1d](https://github.com/ppat/coder/commit/d7c8f1db65c9433ba3336fa0cb84d3c148567989))
* release workflow to publish workspace image to registry and template to coder ([#7](https://github.com/ppat/coder/issues/7)) ([db9e5c7](https://github.com/ppat/coder/commit/db9e5c7ff9b5d432057e8174646c394277218ec8))


### 🐛 Enhancements + Bug Fixes

* only release workflow testing runs should publish w/ suffix '-test' ([#15](https://github.com/ppat/coder/issues/15)) ([3ef10e7](https://github.com/ppat/coder/commit/3ef10e7f7d4ac6e7219a25a19f41fb1a2fe12a77))


### 🛠 Improvements

* change the build of workspace image steps ([#12](https://github.com/ppat/coder/issues/12)) ([de1cb72](https://github.com/ppat/coder/commit/de1cb72f7751450f67753acdf225d7d8f99c7350))
* fix testing of release workflow ([#13](https://github.com/ppat/coder/issues/13)) ([a44b67d](https://github.com/ppat/coder/commit/a44b67d25bf5b6ba0312adbe0edbb92a788551ea))


### ⚙️ Other

* add renovate config package rule upgrading ubuntu major versions ([#8](https://github.com/ppat/coder/issues/8)) ([8c19dbe](https://github.com/ppat/coder/commit/8c19dbe0852ed27b03fa8bb44d20060c1c700b91))
* first commit ([e27a8a5](https://github.com/ppat/coder/commit/e27a8a5f325a1678212a38a7d117c93be072bc94))
* fix release workflow by adding missing required file ([#14](https://github.com/ppat/coder/issues/14)) ([29373a7](https://github.com/ppat/coder/commit/29373a7be8b4cc14b0e8e8354dca2e75b17503c0))


### 📌 Dependencies

* **deps:** update github-release non-major dependencies ([#2](https://github.com/ppat/coder/issues/2)) ([a678a1e](https://github.com/ppat/coder/commit/a678a1e21235c45f641faf56b85b2bc3db0ca2b9))
* **deps:** update npm non-major dependencies ([#3](https://github.com/ppat/coder/issues/3)) ([d40e121](https://github.com/ppat/coder/commit/d40e121a4bbb78afaa5aabea6d8df893606df939))
* **deps:** update postgres docker tag to v16 ([#11](https://github.com/ppat/coder/issues/11)) ([0a6b3d4](https://github.com/ppat/coder/commit/0a6b3d4d10bc6d85955e2da2c407a8ec9a91d5c2))
