# Changelog



## [1.7.4](https://github.com/ppat/coder/compare/v1.7.3...v1.7.4) (2024-07-19)

### 🐛 Enhancements + Bug Fixes

* fix workspace initialization scripts ([#108](https://github.com/ppat/coder/issues/108)) ([51dc6b3](https://github.com/ppat/coder/commit/51dc6b3a78b5c45400f70df6e36e26ca5735dac3))

### 🛠 Improvements

* use base ubuntu:noble image for testing template ([#109](https://github.com/ppat/coder/issues/109)) ([06b7f9e](https://github.com/ppat/coder/commit/06b7f9eecb35adfcb4087b3798e0e7a1614303c7))

### 📌 Dependencies

* **deps:** update dependency bootandy/dust to v1.1.0 ([#106](https://github.com/ppat/coder/issues/106)) ([f8e8966](https://github.com/ppat/coder/commit/f8e89664888d1da74ab54da15ded7daaf24d263f))
* **deps:** update github-release non-major dependencies ([#107](https://github.com/ppat/coder/issues/107)) ([7fb736b](https://github.com/ppat/coder/commit/7fb736b71890cccc9f0767a4e1e3d0ee560c9c9a))

## [1.7.3](https://github.com/ppat/coder/compare/v1.7.2...v1.7.3) (2024-07-16)

### 🐛 Enhancements + Bug Fixes

* various fixes to workspace initialization scripts ([#105](https://github.com/ppat/coder/issues/105)) ([41367a7](https://github.com/ppat/coder/commit/41367a7b7c3c633889c22ba165591f0acde0e1a0))

### 📌 Dependencies

* **deps:** update dependency community.general to v9.2.0 ([#101](https://github.com/ppat/coder/issues/101)) ([893cfc7](https://github.com/ppat/coder/commit/893cfc72ab55326f65a91a48c39b2b30f6adc493))

## [1.7.2](https://github.com/ppat/coder/compare/v1.7.1...v1.7.2) (2024-07-14)

### 🐛 Enhancements + Bug Fixes

* run workspace initialization scripts in background when possible to speed up start up ([#100](https://github.com/ppat/coder/issues/100)) ([4f582c6](https://github.com/ppat/coder/commit/4f582c6080251240ea31a1441a0a04f5e6ee4e09))

## [1.7.1](https://github.com/ppat/coder/compare/v1.7.0...v1.7.1) (2024-07-14)

### 🐛 Enhancements + Bug Fixes

* fix workspace entrypoint script ([#99](https://github.com/ppat/coder/issues/99)) ([c58479a](https://github.com/ppat/coder/commit/c58479accc4ef607b5114cf13490e793c1c2b671))

## [1.7.0](https://github.com/ppat/coder/compare/v1.6.0...v1.7.0) (2024-07-14)

### ✨ Features

* replace systemd with supervisord in coder image ([#98](https://github.com/ppat/coder/issues/98)) ([02b1759](https://github.com/ppat/coder/commit/02b17599ffebab12d60439ce98464e844a6af961))

### 📌 Dependencies

* **deps:** update terraform coder to v1.0.1 ([#96](https://github.com/ppat/coder/issues/96)) ([e89b8c7](https://github.com/ppat/coder/commit/e89b8c744d7d0eb8f7cb500ac3e14546b914ed5f))

## [1.6.0](https://github.com/ppat/coder/compare/v1.5.2...v1.6.0) (2024-07-13)

### ✨ Features

* update coder workspace images to ubuntu:noble ([#95](https://github.com/ppat/coder/issues/95)) ([976b4f5](https://github.com/ppat/coder/commit/976b4f560e77b95bdafae5fa4c0b1b9fb7f5a95b))

### 🐛 Enhancements + Bug Fixes

* drop tfsec from coder workspace image ([#90](https://github.com/ppat/coder/issues/90)) ([973f6e9](https://github.com/ppat/coder/commit/973f6e9ae79caef21613fc0f8b24b1557f0cd565))

### 📌 Dependencies

* **deps:** lock file maintenance ([#94](https://github.com/ppat/coder/issues/94)) ([1e96f97](https://github.com/ppat/coder/commit/1e96f979616562b633c828d8d17f01a5e10a9e2c))
* **deps:** update github-action dependencies ([#91](https://github.com/ppat/coder/issues/91)) ([eb4f1fe](https://github.com/ppat/coder/commit/eb4f1feb4dcbcd15607b217d7a79d0d321714772))
* **deps:** update terraform coder to v1 ([#92](https://github.com/ppat/coder/issues/92)) ([b4b48f8](https://github.com/ppat/coder/commit/b4b48f856cf6c17f53bc4b73d401391e6e296776))

## [1.5.2](https://github.com/ppat/coder/compare/v1.5.1...v1.5.2) (2024-07-12)

### 📌 Dependencies

* **deps:** update dependency community.docker to v3.11.0 ([#80](https://github.com/ppat/coder/issues/80)) ([11f7742](https://github.com/ppat/coder/commit/11f7742e14a4baf9fe75ac784c39122e3d616ad7))
* **deps:** update dependency helm/helm to v3.15.3 ([#81](https://github.com/ppat/coder/issues/81)) ([8f0b412](https://github.com/ppat/coder/commit/8f0b412a88bd0355b76fb70db5b5d9c5f317bb8e))
* **deps:** update dependency molecule to v24.6.1 ([#75](https://github.com/ppat/coder/issues/75)) ([3da462b](https://github.com/ppat/coder/commit/3da462b71284850fa6f6d331fbd48e842769c0e6))
* **deps:** update dependency node to v20.15.1 ([#86](https://github.com/ppat/coder/issues/86)) ([cd05606](https://github.com/ppat/coder/commit/cd05606159fbd134ed2be45c4f968feff183a087))
* **deps:** update dependency terraform-linters/tflint to v0.52.0 ([#77](https://github.com/ppat/coder/issues/77)) ([21d7f42](https://github.com/ppat/coder/commit/21d7f428c9681293ebc7ff26b00566e2b03448c3))
* **deps:** update postgres:16.3 docker digest to 0aafd2a ([#84](https://github.com/ppat/coder/issues/84)) ([e3bdd02](https://github.com/ppat/coder/commit/e3bdd020dbe731eda8b6d8cd157c1fdd62bd2f71))
* **deps:** update python non-major dependencies ([#74](https://github.com/ppat/coder/issues/74)) ([d9be3f3](https://github.com/ppat/coder/commit/d9be3f3e1d3e5555b8dde70535d86ddd9435e744))
* **deps:** update python non-major dependencies to v24.7.0 ([#82](https://github.com/ppat/coder/issues/82)) ([4b76bb1](https://github.com/ppat/coder/commit/4b76bb18c050409ca3e0c4218afe5357b6d2bedf))
* **deps:** update ubuntu:jammy docker digest to 340d9b0 ([#85](https://github.com/ppat/coder/issues/85)) ([3a8e2d1](https://github.com/ppat/coder/commit/3a8e2d1936101df0f2a922ad1e8d6f7a6abae68f))

## [1.5.1](https://github.com/ppat/coder/compare/v1.5.0...v1.5.1) (2024-07-05)

### 🐛 Enhancements + Bug Fixes

* fix up some misc bugs in workspace template and image ([#72](https://github.com/ppat/coder/issues/72)) ([fff57a3](https://github.com/ppat/coder/commit/fff57a33259d3a322eced36d892cf6a3e14c13ef))
* improve workspace image build performance ([#71](https://github.com/ppat/coder/issues/71)) ([a568b74](https://github.com/ppat/coder/commit/a568b742b51e5e2794c7e4d531a4724257619255))

## [1.5.0](https://github.com/ppat/coder/compare/v1.4.1...v1.5.0) (2024-07-05)

### ✨ Features

* install and upgrade kubectl plugins ([#67](https://github.com/ppat/coder/issues/67)) ([9ee80c3](https://github.com/ppat/coder/commit/9ee80c3e3e35c66282d95a6a4b9fecd0db52e9a2))

### 🐛 Enhancements + Bug Fixes

* optimize the order of sys package installation ([#69](https://github.com/ppat/coder/issues/69)) ([a71a6af](https://github.com/ppat/coder/commit/a71a6af9631d6fe77c6e8fbfc4164fef68082ece))
* re-use docker image build workflow from ppat/images ([#66](https://github.com/ppat/coder/issues/66)) ([bea2e38](https://github.com/ppat/coder/commit/bea2e38e623dc59a7e6788d4605115ed027f2e6c))
* temporarily drop exa support ([#68](https://github.com/ppat/coder/issues/68)) ([34249db](https://github.com/ppat/coder/commit/34249db5843565b1613c12fb0f42a30294165f94))

### 📌 Dependencies

* **deps:** update dependency golang to v1.22.5 ([#65](https://github.com/ppat/coder/issues/65)) ([61b59ef](https://github.com/ppat/coder/commit/61b59efbf489342cbaa331957bf1daf4069ea10d))
* **deps:** update dependency ipython to v8.26.0 ([#47](https://github.com/ppat/coder/issues/47)) ([0389e99](https://github.com/ppat/coder/commit/0389e99b585c3181248838e8ae7d0e91b0cb367c))
* **deps:** update github-release non-major dependencies ([#55](https://github.com/ppat/coder/issues/55)) ([76773da](https://github.com/ppat/coder/commit/76773dadb018af6c4376a9d043f33608920cc048))
* **deps:** update python major dependencies to v24 (major) ([#62](https://github.com/ppat/coder/issues/62)) ([373310c](https://github.com/ppat/coder/commit/373310c01de76306961cebca251559017cc4d57f))

## [1.4.1](https://github.com/ppat/coder/compare/v1.4.0...v1.4.1) (2024-06-30)

### 🐛 Enhancements + Bug Fixes

* update shell configurations - autocompletions, alias and environment ([#61](https://github.com/ppat/coder/issues/61)) ([16aa034](https://github.com/ppat/coder/commit/16aa0349d25fae866e41cb793a545cb44ddb689e))

## [1.4.0](https://github.com/ppat/coder/compare/v1.3.0...v1.4.0) (2024-06-30)

### ✨ Features

* add github-cli to coder image ([#57](https://github.com/ppat/coder/issues/57)) ([7196078](https://github.com/ppat/coder/commit/71960788873d60b752239165d0ab6a7112979364))

### 🐛 Enhancements + Bug Fixes

* do not add RUSTUP_HOME to image, add it at workspace start up ([#59](https://github.com/ppat/coder/issues/59)) ([2844099](https://github.com/ppat/coder/commit/284409938342c60d0d81f88897db3e4a83ef06a9))
* refactor to ensure that docker build cache id's are unique ([#60](https://github.com/ppat/coder/issues/60)) ([91b19d8](https://github.com/ppat/coder/commit/91b19d86dce0e110737eff572a59d89ad31f306d))

## [1.3.0](https://github.com/ppat/coder/compare/v1.2.0...v1.3.0) (2024-06-30)

### ✨ Features

* add rust/cargo sdk and some rust cli tools ([#52](https://github.com/ppat/coder/issues/52)) ([fc271b9](https://github.com/ppat/coder/commit/fc271b9043e02ee223eb29025c649a6bfac336ac))
* add various new CLI tools to coder image ([#54](https://github.com/ppat/coder/issues/54)) ([135eb03](https://github.com/ppat/coder/commit/135eb03b2880bd8fc2a5ebac58cb17826debb23b))

### 🐛 Enhancements + Bug Fixes

* move python packages + ansible collections in coder image into its own build stage ([#53](https://github.com/ppat/coder/issues/53)) ([f047731](https://github.com/ppat/coder/commit/f0477312c2b3ce507a604f34df4ce4c48d767771))
* temporarily remove rust-compiled binaries from coder image ([#56](https://github.com/ppat/coder/issues/56)) ([4250a68](https://github.com/ppat/coder/commit/4250a68237b03f96434e28fd4c24d998bc68433c))

## [1.2.0](https://github.com/ppat/coder/compare/v1.1.2...v1.2.0) (2024-06-29)

### ✨ Features

* add kind cli to coder image ([#51](https://github.com/ppat/coder/issues/51)) ([cc67aec](https://github.com/ppat/coder/commit/cc67aecd34a7e32569620e3bbc905bbd3cdd4475))

### 🐛 Enhancements + Bug Fixes

* fix installation of starship from agent-startup-script ([#50](https://github.com/ppat/coder/issues/50)) ([1b5d818](https://github.com/ppat/coder/commit/1b5d818c9d86a702628225f082503f3ae46352cf))
* various image updates ([#49](https://github.com/ppat/coder/issues/49)) ([52f337c](https://github.com/ppat/coder/commit/52f337cf1a0d64b4402b21dc40a5d213b9150c5a))

## [1.1.2](https://github.com/ppat/coder/compare/v1.1.1...v1.1.2) (2024-06-29)

### 📌 Dependencies

* **deps:** update dependency ansible-core to v2.17.1 ([#43](https://github.com/ppat/coder/issues/43)) ([9f3fdb5](https://github.com/ppat/coder/commit/9f3fdb58dccaa3cfd29a5a0f5cc518e7fc8c747f))
* **deps:** update dependency aquasecurity/tfsec to v1.28.9 ([#46](https://github.com/ppat/coder/issues/46)) ([475675f](https://github.com/ppat/coder/commit/475675fb9132e333c93f6ea393ded75ccc61b3aa))

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
