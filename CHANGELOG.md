# Changelog



## [2.5.0](https://github.com/ppat/coder/compare/v2.4.1...v2.5.0) (2025-01-22)

### ✨ Features

* add an init-container to workspace pod to initialize apt-cache ([#424](https://github.com/ppat/coder/issues/424)) ([d3605dc](https://github.com/ppat/coder/commit/d3605dcf920f7345662d815aba1cada33ed94c22))

### 🐛 Enhancements + Bug Fixes

* add more apt packages to workspace image ([#423](https://github.com/ppat/coder/issues/423)) ([e379526](https://github.com/ppat/coder/commit/e379526f24388b6524e9e24fd27ec63fa88f8dfa))

## [2.4.1](https://github.com/ppat/coder/compare/v2.4.0...v2.4.1) (2025-01-22)

### 🐛 Enhancements + Bug Fixes

* streamline the workspace image by dropping unnecessarily large packages (incl. of their transitive dependencies) ([#422](https://github.com/ppat/coder/issues/422)) ([37cf0b8](https://github.com/ppat/coder/commit/37cf0b83605969b23704f3051b17370b4e83dcf6))

## [2.4.0](https://github.com/ppat/coder/compare/v2.3.0...v2.4.0) (2025-01-22)

### ✨ Features

* **cli-tools:** update aquaproj/aqua (v2.41.0 -> v2.42.2) ([#407](https://github.com/ppat/coder/issues/407)) ([ff9e595](https://github.com/ppat/coder/commit/ff9e595135f01f2d742ec21edf5afb058468d980))
* **cli-tools:** update starship/starship (v1.21.1 -> v1.22.1) ([#419](https://github.com/ppat/coder/issues/419)) ([e5fed54](https://github.com/ppat/coder/commit/e5fed543594881051ef3b9ef21780544ef2517ba))
* **terraform-provider:** update coder/coder (2.0.2 -> 2.1.0) ([#373](https://github.com/ppat/coder/issues/373)) ([f0faa83](https://github.com/ppat/coder/commit/f0faa833349cf97d0466c94d8fc281045aff9b8a))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update jdx/mise (v2025.1.2 -> v2025.1.3) ([#406](https://github.com/ppat/coder/issues/406)) ([8927559](https://github.com/ppat/coder/commit/8927559058803aaadd69032239526dfd865cad64))
* **cli-tools:** update jdx/mise (v2025.1.3 -> v2025.1.4) ([#410](https://github.com/ppat/coder/issues/410)) ([83f8722](https://github.com/ppat/coder/commit/83f8722394159786fe259116bfa896fb2abb22ee))
* **cli-tools:** update jdx/mise (v2025.1.4 -> v2025.1.5) ([#411](https://github.com/ppat/coder/issues/411)) ([ffb59dc](https://github.com/ppat/coder/commit/ffb59dc459e63196c2b1a970c2c2d9f38a9eb78e))
* **cli-tools:** update jdx/mise (v2025.1.5 -> v2025.1.7) ([#417](https://github.com/ppat/coder/issues/417)) ([d9fe381](https://github.com/ppat/coder/commit/d9fe3810d2b7e1b65124e70b35ce94c6fe1e4daa))
* **cli-tools:** update jdx/mise (v2025.1.7 -> v2025.1.9) ([#418](https://github.com/ppat/coder/issues/418)) ([7cb9206](https://github.com/ppat/coder/commit/7cb9206660895287d7974e268473aceb2f41b907))
* **github-actions:** switch coder image build workflow to be from github-workflows repo ([#420](https://github.com/ppat/coder/issues/420)) ([474ddf3](https://github.com/ppat/coder/commit/474ddf3dbc75e0ab925fd3370ae5a82132fb05b4))

## [2.3.0](https://github.com/ppat/coder/compare/v2.2.0...v2.3.0) (2025-01-10)

### ✨ Features

* **terraform-version:** update terraform-1.10.3 (1.9.8 -> 1.10.3) ([#396](https://github.com/ppat/coder/issues/396)) ([0b37773](https://github.com/ppat/coder/commit/0b37773d837af03546f4caf740a3ba2884e764b3))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update jdx/mise (v2025.1.0 -> v2025.1.1) ([#398](https://github.com/ppat/coder/issues/398)) ([bad47a8](https://github.com/ppat/coder/commit/bad47a8e1590a4ce2c7a044eb84f66f1319b8e85))
* **cli-tools:** update jdx/mise (v2025.1.1 -> v2025.1.2) ([#401](https://github.com/ppat/coder/issues/401)) ([49eafb7](https://github.com/ppat/coder/commit/49eafb7e4e43211543f356f8ad30f572f912cdb1))
* drop unused packages from workspace image ([#402](https://github.com/ppat/coder/issues/402)) ([ab22004](https://github.com/ppat/coder/commit/ab2200409d32af288ce237e2c26a374d47420687))
* **terraform-version:** update terraform (1.10.3 -> 1.10.4) ([#400](https://github.com/ppat/coder/issues/400)) ([2082570](https://github.com/ppat/coder/commit/20825700ee599be201fce241b7fe4c69dfeae52a))
* update registry.coder.com/modules/coder-login/coder (v1.0.26 -> v1.0.27) ([#399](https://github.com/ppat/coder/issues/399)) ([0441193](https://github.com/ppat/coder/commit/0441193e1ec27ecdea13edf829bbeeca2c794580))

### 🛠 Improvements

* fix formatting ([4e291f1](https://github.com/ppat/coder/commit/4e291f11f7a39bfa365d44c2c7c3a895f7e9c19f))

## [2.2.0](https://github.com/ppat/coder/compare/v2.1.2...v2.2.0) (2025-01-04)

### ✨ Features

* **cli-tools:** update aquaproj/aqua (v2.40.0 -> v2.41.0) ([#389](https://github.com/ppat/coder/issues/389)) ([1a2561e](https://github.com/ppat/coder/commit/1a2561e62af2fc56dc67a1981b0adb86fd916155))
* **cli-tools:** update jdx/mise (v2024.12.24 -> v2025.1.0) ([#390](https://github.com/ppat/coder/issues/390)) ([1b596f8](https://github.com/ppat/coder/commit/1b596f8f611eda28435403cf9e5c0b21b1946343))

### 🐛 Enhancements + Bug Fixes

* clean up coder agent startup script ([#391](https://github.com/ppat/coder/issues/391)) ([d7328b3](https://github.com/ppat/coder/commit/d7328b30bdb4f461151e877359f076c4380b7858))
* **cli-tools:** update jdx/mise (v2024.12.21 -> v2024.12.22) ([#381](https://github.com/ppat/coder/issues/381)) ([8a28915](https://github.com/ppat/coder/commit/8a28915e50e5675186a4e7edda6c940864981931))
* **cli-tools:** update jdx/mise (v2024.12.22 -> v2024.12.24) ([#386](https://github.com/ppat/coder/issues/386)) ([afdd4a1](https://github.com/ppat/coder/commit/afdd4a1d9762feb8dd17cdabc9b2e13de7b4ca62))

## [2.1.2](https://github.com/ppat/coder/compare/v2.1.1...v2.1.2) (2024-12-28)

### 🐛 Enhancements + Bug Fixes

* fix ownership for mise-en-place cli tool ([#380](https://github.com/ppat/coder/issues/380)) ([bae0533](https://github.com/ppat/coder/commit/bae053313772b4fe0f70697cc960381f2bb59e3e))

## [2.1.1](https://github.com/ppat/coder/compare/v2.1.0...v2.1.1) (2024-12-28)

### 🐛 Enhancements + Bug Fixes

* drop fnm and tfenv from image as part of switch to mise-en-place ([#379](https://github.com/ppat/coder/issues/379)) ([511e73c](https://github.com/ppat/coder/commit/511e73c024b9f0e3d4a7d777fd6961bf9e04c850))
* only retain cli-tools needed for baseline workspace (upx, starship, aqua, mise-en-place) ([#378](https://github.com/ppat/coder/issues/378)) ([89b6457](https://github.com/ppat/coder/commit/89b64572dcb4495d1f7aa5a07f7df74f4ba8176b))
* remove __pycache__ directories from docker image ([#377](https://github.com/ppat/coder/issues/377)) ([ec3296b](https://github.com/ppat/coder/commit/ec3296bb53adf89f2cc7fe5f898cbab2c9216e2c))

## [2.1.0](https://github.com/ppat/coder/compare/v2.0.3...v2.1.0) (2024-12-28)

### ✨ Features

* **cli-tools:** switch to using aqua for managing most CLI tools instead of baking them into image ([#376](https://github.com/ppat/coder/issues/376)) ([8c119c3](https://github.com/ppat/coder/commit/8c119c3da7bce07d356b4178369e77b24e6efebf))

## [2.0.3](https://github.com/ppat/coder/compare/v2.0.2...v2.0.3) (2024-12-26)

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update helm/helm (v3.16.3 -> v3.16.4) ([#369](https://github.com/ppat/coder/issues/369)) ([e9d24be](https://github.com/ppat/coder/commit/e9d24be9d4287cd07d219025ef4be7433dbad6f3))
* drop unused packages from image ([#372](https://github.com/ppat/coder/issues/372)) ([9890e5f](https://github.com/ppat/coder/commit/9890e5fd38e9a648e9af5d30032d88fcf756cee6))
* **terraform-provider:** update hashicorp/kubernetes (2.35.0 -> 2.35.1) ([#371](https://github.com/ppat/coder/issues/371)) ([46e4668](https://github.com/ppat/coder/commit/46e4668c7d2b2ccb4a3a324e9a991cf20e03751e))
* update registry.coder.com/modules/coder-login/coder (v1.0.25 -> v1.0.26) ([#370](https://github.com/ppat/coder/issues/370)) ([43a01bf](https://github.com/ppat/coder/commit/43a01bfc89d2ce83d5b7ec514d27e85061f5463f))

## [2.0.2](https://github.com/ppat/coder/compare/v2.0.1...v2.0.2) (2024-12-16)

### 🐛 Enhancements + Bug Fixes

* secret should be readable by fs_group id ([#365](https://github.com/ppat/coder/issues/365)) ([70edc4a](https://github.com/ppat/coder/commit/70edc4ab08fb414a285250904a3e9a6f72c28d71))
* streamline image by moving additionals installs to dotfiles scripts ([#366](https://github.com/ppat/coder/issues/366)) ([5d12648](https://github.com/ppat/coder/commit/5d12648fb304dc509c6dd2c660bac337e3b1aac1))

## [2.0.1](https://github.com/ppat/coder/compare/v2.0.0...v2.0.1) (2024-12-16)

### 🐛 Enhancements + Bug Fixes

* update registry.coder.com/modules/coder-login/coder (v1.0.15 -> v1.0.25) ([#362](https://github.com/ppat/coder/issues/362)) ([f8c64e4](https://github.com/ppat/coder/commit/f8c64e47aca19a507788538afa25170fc0f9781c))
* update script-agent-startup.sh ([#364](https://github.com/ppat/coder/issues/364)) ([461de2b](https://github.com/ppat/coder/commit/461de2b74988a57e1e78473709ce4a0f49fd4a01))

## [2.0.0](https://github.com/ppat/coder/compare/v1.15.0...v2.0.0) (2024-12-14)

### ⚠ BREAKING CHANGES

* switch from docker based coder templates to kubernetes based coder template (#361)

### ✨ Features

* switch from docker based coder templates to kubernetes based coder template ([#361](https://github.com/ppat/coder/issues/361)) ([5c4c3a3](https://github.com/ppat/coder/commit/5c4c3a346184841edfb7a93fd4b4b96fc3ab7964))

## [1.15.0](https://github.com/ppat/coder/compare/v1.14.0...v1.15.0) (2024-12-14)

### ✨ Features

* create coder user within image ([#360](https://github.com/ppat/coder/issues/360)) ([b746075](https://github.com/ppat/coder/commit/b7460755a12de4f21c3716d5d6bb333c70ad9598))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update kubernetes/kubernetes (v1.31.3 -> v1.31.4) ([#354](https://github.com/ppat/coder/issues/354)) ([517c6a7](https://github.com/ppat/coder/commit/517c6a7a00e60cadbe9e166fdd9e7e4c59a83173))
* fix dotfiles fetch ([f5c36e3](https://github.com/ppat/coder/commit/f5c36e30cb1fcf9ec1a335a3f6ecd63dcc75291b))

## [1.14.0](https://github.com/ppat/coder/compare/v1.13.0...v1.14.0) (2024-12-11)

### ✨ Features

* **cli-tools:** update cli/cli (v2.62.0 -> v2.63.0) ([#338](https://github.com/ppat/coder/issues/338)) ([5de42fc](https://github.com/ppat/coder/commit/5de42fccd309262e8a27f665c22114a548db51b4))
* **galaxy-collection:** update community.general (10.0.1 -> 10.1.0) ([#334](https://github.com/ppat/coder/issues/334)) ([57e2a53](https://github.com/ppat/coder/commit/57e2a530ff20b05186dab9e1a19e1601e8fb35ca))
* **npm-tools:** update renovate (39.31.3 -> 39.33.0) ([#329](https://github.com/ppat/coder/issues/329)) ([a1e7601](https://github.com/ppat/coder/commit/a1e7601f7679166b555c90352f1811ff1e7b10c5))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update mikefarah/yq (v4.44.5 -> v4.44.6) ([#342](https://github.com/ppat/coder/issues/342)) ([edf79f7](https://github.com/ppat/coder/commit/edf79f7cb2015e699f59556251d4282bb73de6ff))
* **cli-tools:** update nektos/act (v0.2.69 -> v0.2.70) ([#332](https://github.com/ppat/coder/issues/332)) ([a84975d](https://github.com/ppat/coder/commit/a84975d2dfb397e9b3b95a073585932592938fe9))
* **cli-tools:** update starship/starship (v1.21.0 -> v1.21.1) ([#351](https://github.com/ppat/coder/issues/351)) ([92faec5](https://github.com/ppat/coder/commit/92faec5a3955970a93aafcf0dc38fa4bc1ca5a20))
* fix agent startup script ([#352](https://github.com/ppat/coder/issues/352)) ([9e3d280](https://github.com/ppat/coder/commit/9e3d280bd82ca2619e7c4df25b458521db6195fa))
* **lang-sdk:** update golang (1.23.3 -> 1.23.4) ([#345](https://github.com/ppat/coder/issues/345)) ([ab37445](https://github.com/ppat/coder/commit/ab37445108d878b4066c28a1851a3c1d781f5bac))
* move init-scripts from coder image to dotfiles ([#350](https://github.com/ppat/coder/issues/350)) ([2256e79](https://github.com/ppat/coder/commit/2256e799eea8f457d51d29ae1eda53f30f432f21))
* **npm-tools:** update renovate (39.33.0 -> 39.33.1) ([#343](https://github.com/ppat/coder/issues/343)) ([610a3d1](https://github.com/ppat/coder/commit/610a3d182b96cac127f567bf9b93f7fc0e24eae8))
* **pypi-tools:** update ansible-core (2.18.0 -> 2.18.1) ([#346](https://github.com/ppat/coder/issues/346)) ([34a0cce](https://github.com/ppat/coder/commit/34a0cceb73e39838fddeee4692e471e18bb16486))
* update digest ubuntu (278628f -> 80dd3c3) ([#336](https://github.com/ppat/coder/issues/336)) ([f09d457](https://github.com/ppat/coder/commit/f09d457418e9c69133630b59fe75b72462775d9e))

### 🛠 Improvements

* fix test ([#353](https://github.com/ppat/coder/issues/353)) ([afabed2](https://github.com/ppat/coder/commit/afabed2a0f1a9c5c8a72094c1522671193f8c997))

## [1.13.0](https://github.com/ppat/coder/compare/v1.12.1...v1.13.0) (2024-11-27)

### ✨ Features

* **lang-sdk:** update node (v20.18.1 -> v22.11.0) ([#325](https://github.com/ppat/coder/issues/325)) ([513d803](https://github.com/ppat/coder/commit/513d8031b57a5c06857471e317724240323e422d))
* **pypi-tools:** update pip_requirements ([#330](https://github.com/ppat/coder/issues/330)) ([06cece0](https://github.com/ppat/coder/commit/06cece034c2e1600a703f7c9a171d47812a98441))

### 🐛 Enhancements + Bug Fixes

* fix typos in init scripts ([#327](https://github.com/ppat/coder/issues/327)) ([4f8eb5e](https://github.com/ppat/coder/commit/4f8eb5eb03c4372b40f69b9817f08ed3ced667d8))

## [1.12.1](https://github.com/ppat/coder/compare/v1.12.0...v1.12.1) (2024-11-26)

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** move installation of various packages from image to init scripts ([#323](https://github.com/ppat/coder/issues/323)) ([ee12fb7](https://github.com/ppat/coder/commit/ee12fb7bc3a5a11329e1fd9d84e01038f095a0ef))

## [1.12.0](https://github.com/ppat/coder/compare/v1.11.0...v1.12.0) (2024-11-26)

### ✨ Features

* **cli-tools:** update cli/cli (v2.59.0 -> v2.60.1) ([#273](https://github.com/ppat/coder/issues/273)) ([ac7f0c6](https://github.com/ppat/coder/commit/ac7f0c6e9e2f5db9f3ef2e6458422d8ff6777711))
* **cli-tools:** update cli/cli (v2.60.1 -> v2.61.0) ([#293](https://github.com/ppat/coder/issues/293)) ([6da892a](https://github.com/ppat/coder/commit/6da892a0a6f655227b0e2c55eaf1870b9b4040cf))
* **cli-tools:** update cli/cli (v2.61.0 -> v2.62.0) ([#307](https://github.com/ppat/coder/issues/307)) ([2b74e7b](https://github.com/ppat/coder/commit/2b74e7bbc7d9cef5b6bff3bd0cea43433e620d0a))
* **cli-tools:** update kubernetes-sigs/kind (v0.24.0 -> v0.25.0) ([#285](https://github.com/ppat/coder/issues/285)) ([a82b08a](https://github.com/ppat/coder/commit/a82b08a411bbc7c45d51e99b36a0216b3baa9148))
* **cli-tools:** update qarmin/czkawka (7.0.0 -> 8.0.0) ([#282](https://github.com/ppat/coder/issues/282)) ([8bfb791](https://github.com/ppat/coder/commit/8bfb7916fa0bf66be02badea8d7c2d1b98a71ca6))
* **cli-tools:** update schniz/fnm (v1.37.2 -> v1.38.0) ([#308](https://github.com/ppat/coder/issues/308)) ([4b97081](https://github.com/ppat/coder/commit/4b97081fe11a06c64a49512db5b8334e6d483f2a))
* **cli-tools:** update terraform-linters/tflint (v0.53.0 -> v0.54.0) ([#300](https://github.com/ppat/coder/issues/300)) ([a6cd082](https://github.com/ppat/coder/commit/a6cd082fa8a1c3f170f68231f9dd663a591fa706))
* **cli-tools:** update wilfred/difftastic (0.60.0 -> 0.61.0) ([#272](https://github.com/ppat/coder/issues/272)) ([3655fd9](https://github.com/ppat/coder/commit/3655fd923623052e367e9f45dc68d49f5ec3f60c))
* **galaxy-collection:** update community.docker (4.0.1 -> 4.1.0) ([#313](https://github.com/ppat/coder/issues/313)) ([ce331fc](https://github.com/ppat/coder/commit/ce331fc734efa134c417dfbfc90f4c3c0466d763))
* **galaxy-collection:** update community.general (9.5.1 -> 10.0.1) ([#280](https://github.com/ppat/coder/issues/280)) ([9b23a7a](https://github.com/ppat/coder/commit/9b23a7a5af93ef173f6d5023919338e7df755d35))
* **lang-sdk:** update node (v20.17.0 -> v20.18.0) ([#275](https://github.com/ppat/coder/issues/275)) ([0b012e9](https://github.com/ppat/coder/commit/0b012e9174cb4e03d1262d13f77385d2ed0a9dcb))
* **lang-sdk:** update rust-lang/rust (1.81.0 -> 1.82.0) ([#301](https://github.com/ppat/coder/issues/301)) ([8241a3b](https://github.com/ppat/coder/commit/8241a3beacb7775183009213cf651a79f28dc943))
* **npm-tools:** update npm ([#305](https://github.com/ppat/coder/issues/305)) ([3acfe5e](https://github.com/ppat/coder/commit/3acfe5eabaece399a0622eb7bfcb1d564096a2d7))
* **npm-tools:** update npm ([#314](https://github.com/ppat/coder/issues/314)) ([86ea700](https://github.com/ppat/coder/commit/86ea700d0a22a3ab166c7cfb327d2f3862847a0b))
* **npm-tools:** update renovate (38.1.0 -> 38.119.0) ([#270](https://github.com/ppat/coder/issues/270)) ([fa83b97](https://github.com/ppat/coder/commit/fa83b97adc21cd5bc59213df375cde2c0cf13056))
* **npm-tools:** update renovate (38.119.0 -> 38.127.0) ([#297](https://github.com/ppat/coder/issues/297)) ([92ee995](https://github.com/ppat/coder/commit/92ee99555c6d986230920cf21649f2bb0fc682ef))
* **npm-tools:** update renovate (38.119.0 -> 39.19.1) ([#286](https://github.com/ppat/coder/issues/286)) ([6217dee](https://github.com/ppat/coder/commit/6217dee06193429cf8b9fbbd57129e297dc26517))
* **pypi-tools:** update ipython (8.27.0 -> 8.28.0) ([#274](https://github.com/ppat/coder/issues/274)) ([dec2b1d](https://github.com/ppat/coder/commit/dec2b1d7be36436cf14f4c61ff9c297e86a60a18))
* **pypi-tools:** update ipython (8.28.0 -> 8.29.0) ([#315](https://github.com/ppat/coder/issues/315)) ([70c4ad4](https://github.com/ppat/coder/commit/70c4ad4d5f8972f554f7b82e9f30babaed35f69f))
* **pypi-tools:** update pre-commit (3.8.0 -> 4.0.1) ([#287](https://github.com/ppat/coder/issues/287)) ([5daa9ec](https://github.com/ppat/coder/commit/5daa9ec3a36dd281036c2c1a44e3192c0fa8895d))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update derailed/k9s (v0.32.5 -> v0.32.6) ([#290](https://github.com/ppat/coder/issues/290)) ([5ec9e66](https://github.com/ppat/coder/commit/5ec9e6676d97d8a459cf4d519b42ed26292dc3ae))
* **cli-tools:** update derailed/k9s (v0.32.6 -> v0.32.7) ([#303](https://github.com/ppat/coder/issues/303)) ([e1099df](https://github.com/ppat/coder/commit/e1099dfb8f07c6caf2db6b9a958ad83a43b71f71))
* **cli-tools:** update helm/helm (v3.16.2 -> v3.16.3) ([#296](https://github.com/ppat/coder/issues/296)) ([904ce0d](https://github.com/ppat/coder/commit/904ce0d9e238ca48357412efde6319849ca2eda0))
* **cli-tools:** update kubernetes/kubernetes (v1.31.1 -> v1.31.2) ([#269](https://github.com/ppat/coder/issues/269)) ([e7b587e](https://github.com/ppat/coder/commit/e7b587e2879cdb54689782050c5a53605cef545a))
* **cli-tools:** update kubernetes/kubernetes (v1.31.2 -> v1.31.3) ([#309](https://github.com/ppat/coder/issues/309)) ([6169909](https://github.com/ppat/coder/commit/616990993f2840f703d5d35d28bed9f224ffd65f))
* **cli-tools:** update mikefarah/yq (v4.44.3 -> v4.44.5) ([#302](https://github.com/ppat/coder/issues/302)) ([5a165f7](https://github.com/ppat/coder/commit/5a165f77081500c8b867388067b34814dcd2c23a))
* **cli-tools:** update nektos/act (v0.2.68 -> v0.2.69) ([#276](https://github.com/ppat/coder/issues/276)) ([8239bd3](https://github.com/ppat/coder/commit/8239bd34699abcc7f1847ad824473942612291ec))
* **cli-tools:** update rhysd/actionlint (v1.7.3 -> v1.7.4) ([#281](https://github.com/ppat/coder/issues/281)) ([b923a5b](https://github.com/ppat/coder/commit/b923a5bdb01b41c530384164d4c54d7c5e41a359))
* **cli-tools:** update schniz/fnm (v1.38.0 -> v1.38.1) ([#310](https://github.com/ppat/coder/issues/310)) ([36a6413](https://github.com/ppat/coder/commit/36a6413b8d037bdfb99a0987ce9471cac92ab5d3))
* **galaxy-collection:** update galaxy-collection ([#277](https://github.com/ppat/coder/issues/277)) ([9f73e07](https://github.com/ppat/coder/commit/9f73e07c3c8a48d0caecaf0e23546c8d9818b9af))
* **lang-sdk:** update golang (1.23.2 -> 1.23.3) ([#284](https://github.com/ppat/coder/issues/284)) ([174ac44](https://github.com/ppat/coder/commit/174ac44a053a858c794901c23ac34291552d22d1))
* **lang-sdk:** update node (v20.18.0 -> v20.18.1) ([#312](https://github.com/ppat/coder/issues/312)) ([04bbb1e](https://github.com/ppat/coder/commit/04bbb1e4ddf729a02261eb0c181432defc7be55f))
* **pypi-tools:** update ansible-core (2.17.5 -> 2.17.6) ([#291](https://github.com/ppat/coder/issues/291)) ([529c8a8](https://github.com/ppat/coder/commit/529c8a878622fa40d79a50627d5f3ef2d3a4b942))

## [1.11.0](https://github.com/ppat/coder/compare/v1.10.0...v1.11.0) (2024-10-23)

### ✨ Features

* **cli-tools:** update cli/cli (v2.56.0 -> v2.57.0) ([#205](https://github.com/ppat/coder/issues/205)) ([c1e253d](https://github.com/ppat/coder/commit/c1e253dafcd196da856fae9e4a819727b2fe5d15))
* **cli-tools:** update cli/cli (v2.57.0 -> v2.58.0) ([#233](https://github.com/ppat/coder/issues/233)) ([a2411c2](https://github.com/ppat/coder/commit/a2411c21493061a2655daca45d25a124a792430c))
* **cli-tools:** update cli/cli (v2.58.0 -> v2.59.0) ([#262](https://github.com/ppat/coder/issues/262)) ([eb83392](https://github.com/ppat/coder/commit/eb83392a5ced55e718c634d1c5f8cdd50a86d7c9))
* **cli-tools:** update fluxcd/flux2 (v2.3.0 -> v2.4.0) ([#250](https://github.com/ppat/coder/issues/250)) ([b460f7c](https://github.com/ppat/coder/commit/b460f7cd0ea5fbf6638ac56dc716577aa5cec849))
* **cli-tools:** update kubernetes-sigs/kustomize (v5.4.3 -> v5.5.0) ([#251](https://github.com/ppat/coder/issues/251)) ([4022921](https://github.com/ppat/coder/commit/4022921ee2fde97ebc86dc111b752fb73ef82b18))
* **cli-tools:** update kubernetes/kubernetes (v1.30.5 -> v1.31.1) ([#252](https://github.com/ppat/coder/issues/252)) ([a9102dd](https://github.com/ppat/coder/commit/a9102dd5fe7fc2d499d0bbdff26613353a798a47))
* **galaxy-collection:** update community.docker (3.12.2 -> 3.13.0) ([#225](https://github.com/ppat/coder/issues/225)) ([b514655](https://github.com/ppat/coder/commit/b5146552513bca5cc5b92768a37cb5a79905b926))
* **galaxy-collection:** update community.docker (3.13.1 -> 4.0.0) ([#256](https://github.com/ppat/coder/issues/256)) ([7edf35b](https://github.com/ppat/coder/commit/7edf35bb0e461d123e250493503c328f681bac55))
* **galaxy-collection:** update community.general (9.4.0 -> 9.5.0) ([#231](https://github.com/ppat/coder/issues/231)) ([2dd7610](https://github.com/ppat/coder/commit/2dd76102ff8f190189f9db5ebb891df616422aa5))
* **lang-sdk:** update rust-lang/rust (1.80.1 -> 1.81.0) ([#227](https://github.com/ppat/coder/issues/227)) ([061d936](https://github.com/ppat/coder/commit/061d9363b4c8a42c3fbe57c7b2b97a32d949e079))
* **npm-tools:** update @bitwarden/cli (2024.7.2 -> 2024.8.0) ([#203](https://github.com/ppat/coder/issues/203)) ([93f9b6a](https://github.com/ppat/coder/commit/93f9b6ac664046da80d69049d205916b22d68713))
* **npm-tools:** update @bitwarden/cli (2024.8.2 -> 2024.9.0) ([#255](https://github.com/ppat/coder/issues/255)) ([3039ad2](https://github.com/ppat/coder/commit/3039ad2d651a59c5970239e48c6ee63512548195))
* **npm-tools:** update release-please (16.12.2 -> 16.13.0) ([#245](https://github.com/ppat/coder/issues/245)) ([5d3ae56](https://github.com/ppat/coder/commit/5d3ae5644e25b773bdb5dd7b90f0e95437c30fdc))
* **npm-tools:** update release-please (16.13.0 -> 16.14.0) ([#248](https://github.com/ppat/coder/issues/248)) ([90a3e29](https://github.com/ppat/coder/commit/90a3e2961785eef6789850034a5a8921522002ae))
* **npm-tools:** update renovate (37.440.7 -> 38.1.0) ([#263](https://github.com/ppat/coder/issues/263)) ([09ecf7e](https://github.com/ppat/coder/commit/09ecf7ecb2689e0b5d20041507ec34b2821dc979))
* **pypi-tools:** update ipython (8.26.0 -> 8.27.0) ([#211](https://github.com/ppat/coder/issues/211)) ([a6ed81d](https://github.com/ppat/coder/commit/a6ed81df3b8e1e651f4122003de4b82ab8595cd7))
* **pypi-tools:** update kubernetes (30.1.0 -> 31.0.0) ([#253](https://github.com/ppat/coder/issues/253)) ([e905c2d](https://github.com/ppat/coder/commit/e905c2d9037ed2e8686a2f4532427a083e6c4ec1))
* **pypi-tools:** update pip_requirements (24.7.0 -> 24.9.0) ([#238](https://github.com/ppat/coder/issues/238)) ([433f396](https://github.com/ppat/coder/commit/433f3969cb5ef81d3479169f33a30e17e50fac0b))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update hashicorp/terraform (v1.9.6 -> v1.9.7) ([#222](https://github.com/ppat/coder/issues/222)) ([eb11b41](https://github.com/ppat/coder/commit/eb11b41249b37621d31cc86c700b05c4d34d1ee3))
* **cli-tools:** update hashicorp/terraform (v1.9.7 -> v1.9.8) ([#247](https://github.com/ppat/coder/issues/247)) ([d4e047f](https://github.com/ppat/coder/commit/d4e047f28ebbb3322d19ffb32f880f012e2c59b7))
* **cli-tools:** update helm/helm (v3.16.1 -> v3.16.2) ([#234](https://github.com/ppat/coder/issues/234)) ([1699cd0](https://github.com/ppat/coder/commit/1699cd0460c188b076c03321a3566703f7bd3ed4))
* **cli-tools:** update nektos/act (v0.2.67 -> v0.2.68) ([#218](https://github.com/ppat/coder/issues/218)) ([1368797](https://github.com/ppat/coder/commit/1368797e0920e15b4a5bef5c49091ea23fef6c25))
* **cli-tools:** update rhysd/actionlint (v1.7.1 -> v1.7.2) ([#206](https://github.com/ppat/coder/issues/206)) ([4361aaf](https://github.com/ppat/coder/commit/4361aaffa5a1cbac14f3f222ab972db0716b86d8))
* **cli-tools:** update rhysd/actionlint (v1.7.2 -> v1.7.3) ([#215](https://github.com/ppat/coder/issues/215)) ([cbaf960](https://github.com/ppat/coder/commit/cbaf96098c72b15f1f2b9dad247f494c2852c39a))
* **cli-tools:** update schniz/fnm (v1.37.1 -> v1.37.2) ([#228](https://github.com/ppat/coder/issues/228)) ([df603be](https://github.com/ppat/coder/commit/df603be662a65f36cb25904a4162a04d126a792c))
* **galaxy-collection:** update ansible.posix (1.6.0 -> 1.6.1) ([#236](https://github.com/ppat/coder/issues/236)) ([28e99e8](https://github.com/ppat/coder/commit/28e99e873c1758cb579961ac6c6fa59ad90f75bb))
* **galaxy-collection:** update ansible.posix (1.6.1 -> 1.6.2) ([#264](https://github.com/ppat/coder/issues/264)) ([e82439f](https://github.com/ppat/coder/commit/e82439f9e1c826d974065400139efb7daabe777b))
* **galaxy-collection:** update ansible.utils (5.1.1 -> 5.1.2) ([#212](https://github.com/ppat/coder/issues/212)) ([328235e](https://github.com/ppat/coder/commit/328235ee1b27e6d63284a3a068a402cfe9751de1))
* **galaxy-collection:** update community.docker (3.13.0 -> 3.13.1) ([#243](https://github.com/ppat/coder/issues/243)) ([d8a73a7](https://github.com/ppat/coder/commit/d8a73a7cfbb62b43c1fdf358bd37e697b9609751))
* **lang-sdk:** update golang (1.23.1 -> 1.23.2) ([#230](https://github.com/ppat/coder/issues/230)) ([a6f4847](https://github.com/ppat/coder/commit/a6f484777910deb70208d74e7ef1726cc19023af))
* **npm-tools:** update @bitwarden/cli (2024.8.0 -> 2024.8.2) ([#204](https://github.com/ppat/coder/issues/204)) ([87a37bc](https://github.com/ppat/coder/commit/87a37bc0d1d4d278c656ff8baaa74855ad58ff1b))
* **npm-tools:** update release-please (16.14.0 -> 16.14.2) ([#249](https://github.com/ppat/coder/issues/249)) ([60ab925](https://github.com/ppat/coder/commit/60ab925e4355bb7503fde3f9fc82172a97e49e7e))
* **npm-tools:** update release-please (16.14.2 -> 16.14.3) ([#260](https://github.com/ppat/coder/issues/260)) ([8cd5632](https://github.com/ppat/coder/commit/8cd5632118e6baac576fccc32db5bdc35ce7cfc1))
* **pypi-tools:** update ansible-core (2.17.4 -> 2.17.5) ([#241](https://github.com/ppat/coder/issues/241)) ([390f189](https://github.com/ppat/coder/commit/390f18989e32fb561676a5c2a91411434d3d8037))
* **pypi-tools:** update ansible-lint (24.9.0 -> 24.9.2) ([#239](https://github.com/ppat/coder/issues/239)) ([4ec3aa8](https://github.com/ppat/coder/commit/4ec3aa83e71a658af84afcd9b3c7b20bff4766f1))
* **pypi-tools:** update poetry (1.8.3 -> 1.8.4) ([#261](https://github.com/ppat/coder/issues/261)) ([4e5c9d7](https://github.com/ppat/coder/commit/4e5c9d7dadcd5cdb4904567ce27e23ae69cc1f41))
* **terraform-provider:** update coder/coder (1.0.2 -> 1.0.3) ([#216](https://github.com/ppat/coder/issues/216)) ([ad3fb1f](https://github.com/ppat/coder/commit/ad3fb1f87c3b90da3e3b4ecd4c6b27269f0ed7b6))
* **terraform-provider:** update coder/coder (1.0.3 -> 1.0.4) ([#244](https://github.com/ppat/coder/issues/244)) ([84f6ad4](https://github.com/ppat/coder/commit/84f6ad453474c407c35cc8094bf89828d4bd6b9d))

## [1.10.0](https://github.com/ppat/coder/compare/v1.9.0...v1.10.0) (2024-09-21)

### ✨ Features

* add release-please npm package ([#191](https://github.com/ppat/coder/issues/191)) ([ea65dfd](https://github.com/ppat/coder/commit/ea65dfdef37adb4ea06f9042b129a03d0fbd78a0))
* **cli-tools:** update cli/cli (v2.55.0 -> v2.56.0) ([#188](https://github.com/ppat/coder/issues/188)) ([c858fa9](https://github.com/ppat/coder/commit/c858fa9b825eeee1cd6d624175a96079c1d44d11))
* **cli-tools:** update helm/helm (v3.15.4 -> v3.16.0) ([#195](https://github.com/ppat/coder/issues/195)) ([1ee7749](https://github.com/ppat/coder/commit/1ee77497bdfa20e8e42f713e3a748e03cc50c5d2))
* **lang-sdk:** update node (v20.16.0 -> v20.17.0) ([#200](https://github.com/ppat/coder/issues/200)) ([bee63fc](https://github.com/ppat/coder/commit/bee63fc9f34f6b3edf4e839bd08732d6539aef0f))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update ajeetdsouza/zoxide (v0.9.5 -> v0.9.6) ([#201](https://github.com/ppat/coder/issues/201)) ([0b61491](https://github.com/ppat/coder/commit/0b6149184e193f0165fcc7a83f605cdb28a4a486))
* **cli-tools:** update hashicorp/terraform (v1.9.5 -> v1.9.6) ([#197](https://github.com/ppat/coder/issues/197)) ([9d39270](https://github.com/ppat/coder/commit/9d392701f3d12d245ab4f5ff58302eecf4b33c98))
* **cli-tools:** update helm/helm (v3.16.0 -> v3.16.1) ([#198](https://github.com/ppat/coder/issues/198)) ([05f0e59](https://github.com/ppat/coder/commit/05f0e591309031627ce1fb3a113d11b1476ced3d))
* **galaxy-collection:** update community.docker (3.12.1 -> 3.12.2) ([#192](https://github.com/ppat/coder/issues/192)) ([d3b96a2](https://github.com/ppat/coder/commit/d3b96a22c0912aa9ad1ed2006ed9c9413f22bdc7))
* **pypi-tools:** update ansible-core (2.17.3 -> 2.17.4) ([#189](https://github.com/ppat/coder/issues/189)) ([395baaa](https://github.com/ppat/coder/commit/395baaa8ba5316c3154304569df6506c5a3172e2))

## [1.9.0](https://github.com/ppat/coder/compare/v1.8.1...v1.9.0) (2024-09-16)

### ✨ Features

* **cli-tools:** update cli/cli (v2.53.0 -> v2.55.0) ([#169](https://github.com/ppat/coder/issues/169)) ([fe3fb4d](https://github.com/ppat/coder/commit/fe3fb4dcd4f82492105763f4cb2a12d9c9711361))
* **cli-tools:** update hashicorp/packer (v1.10.3 -> v1.11.0) ([#157](https://github.com/ppat/coder/issues/157)) ([1a30811](https://github.com/ppat/coder/commit/1a3081110851b794da47dff851daded7b28e2f5a))
* **cli-tools:** update kubernetes-sigs/kustomize (v5.2.1 -> v5.4.2) ([#162](https://github.com/ppat/coder/issues/162)) ([cd65576](https://github.com/ppat/coder/commit/cd6557653c94375a9a4da9c89d5bf1e96f351cb8))
* **galaxy-collection:** update ansible.posix (1.5.4 -> 1.6.0) ([#179](https://github.com/ppat/coder/issues/179)) ([8f0ac6c](https://github.com/ppat/coder/commit/8f0ac6c5ae02029e13a1ab67410f987c182caba0))
* **galaxy-collection:** update community.general (9.3.0 -> 9.4.0) ([#173](https://github.com/ppat/coder/issues/173)) ([05f9476](https://github.com/ppat/coder/commit/05f9476e5a10a778ef77b0979c9ac83d0adb401f))
* **lang-sdk:** update golang (1.22.7 -> 1.23.0) ([#177](https://github.com/ppat/coder/issues/177)) ([b0b267f](https://github.com/ppat/coder/commit/b0b267f9e78e6cc6c9c2f2ff23076ecfc626ba5c))
* **npm-tools:** update npm ([#151](https://github.com/ppat/coder/issues/151)) ([5db0d5e](https://github.com/ppat/coder/commit/5db0d5eca9aca38354fe89e16123c9c909157eec))
* **pypi-tools:** update molecule (24.7.0 -> 24.8.0) ([#186](https://github.com/ppat/coder/issues/186)) ([25fa46d](https://github.com/ppat/coder/commit/25fa46d14388293bf33b0be3b1323424a811bfd2))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** update ajeetdsouza/zoxide (v0.9.4 -> v0.9.5) ([#184](https://github.com/ppat/coder/issues/184)) ([4e0b215](https://github.com/ppat/coder/commit/4e0b215f349f999acb84a811386aef174a23d867))
* **cli-tools:** update dandavison/delta (0.18.1 -> 0.18.2) ([#180](https://github.com/ppat/coder/issues/180)) ([a4216ba](https://github.com/ppat/coder/commit/a4216bab5f20d838a2abf94c5140f51dec1f1635))
* **cli-tools:** update hashicorp/packer (v1.11.0 -> v1.11.2) ([#168](https://github.com/ppat/coder/issues/168)) ([44aa93f](https://github.com/ppat/coder/commit/44aa93f1624d019ada39af7bd4f7272d5ae46568))
* **cli-tools:** update hashicorp/terraform (v1.9.1 -> v1.9.5) ([#159](https://github.com/ppat/coder/issues/159)) ([acbcb82](https://github.com/ppat/coder/commit/acbcb824bd8f894f2dd7980bad6597cc44ef73bf))
* **cli-tools:** update kubernetes-sigs/kustomize (v5.4.2 -> v5.4.3) ([#165](https://github.com/ppat/coder/issues/165)) ([1fd67ad](https://github.com/ppat/coder/commit/1fd67adcc244e6e65da0fe0da430fe5d523de2d9))
* **cli-tools:** update kubernetes/kubernetes (v1.30.4 -> v1.30.5) ([#181](https://github.com/ppat/coder/issues/181)) ([c8aeb7a](https://github.com/ppat/coder/commit/c8aeb7a8968a0b869bd20a138de01f68ab415c16))
* **cli-tools:** update nektos/act (v0.2.65 -> v0.2.66) ([#160](https://github.com/ppat/coder/issues/160)) ([ca55223](https://github.com/ppat/coder/commit/ca55223a847a43e25ae4505bb19804de956344ca))
* **cli-tools:** update nektos/act (v0.2.66 -> v0.2.67) ([#175](https://github.com/ppat/coder/issues/175)) ([76a70d6](https://github.com/ppat/coder/commit/76a70d6f7875b2c2e18b8c4bb5417b2ba1dcaee2))
* **galaxy-collection:** update ansible.utils (5.1.0 -> 5.1.1) ([#167](https://github.com/ppat/coder/issues/167)) ([18199fb](https://github.com/ppat/coder/commit/18199fb49c5b99240c68de848102074d7eff47d0))
* **lang-sdk:** update golang (1.22.6 -> 1.22.7) ([#176](https://github.com/ppat/coder/issues/176)) ([d34b768](https://github.com/ppat/coder/commit/d34b768beb4f3339c670d2b1290faa4c2c217f0e))
* **lang-sdk:** update golang (1.23.0 -> 1.23.1) ([#183](https://github.com/ppat/coder/issues/183)) ([fedc335](https://github.com/ppat/coder/commit/fedc33574e9012d5cfbd0b9e7b861e7503b35eb2))
* **lang-sdk:** update rust-lang/rust (1.80.0 -> 1.80.1) ([#178](https://github.com/ppat/coder/issues/178)) ([ea4e606](https://github.com/ppat/coder/commit/ea4e6065804bcaeb2a5bd9d2b719f700cd89388c))
* **terraform-provider:** update coder/coder (1.0.1 -> 1.0.2) ([#174](https://github.com/ppat/coder/issues/174)) ([9fa74ad](https://github.com/ppat/coder/commit/9fa74ade58d5a7df23259b84bdf3634d9b140f65))

## [1.8.1](https://github.com/ppat/coder/compare/v1.8.0...v1.8.1) (2024-09-03)

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** fix github-releases install at agent-startup ([#163](https://github.com/ppat/coder/issues/163)) ([aaa9162](https://github.com/ppat/coder/commit/aaa9162b7a30487d4e5eb407b622e7b3a490af8e))

## [1.8.0](https://github.com/ppat/coder/compare/v1.7.6...v1.8.0) (2024-09-03)

### ✨ Features

* **cli-tools:** update dandavison/delta (0.17.0 -> 0.18.0) ([#147](https://github.com/ppat/coder/issues/147)) ([415b7da](https://github.com/ppat/coder/commit/415b7da19dad45256c735572d58bcf3e505a6560))
* **cli-tools:** update hashicorp/terraform (v1.8.5 -> v1.9.1) ([#152](https://github.com/ppat/coder/issues/152)) ([ce5343c](https://github.com/ppat/coder/commit/ce5343c030553337913950f5ad3305de72b0ba90))
* **cli-tools:** update kubernetes-sigs/kind (v0.23.0 -> v0.24.0) ([#145](https://github.com/ppat/coder/issues/145)) ([c7983ce](https://github.com/ppat/coder/commit/c7983ceaf80453097adee9cb40c6e5766ff431fc))
* **cli-tools:** update terraform-linters/tflint (v0.52.0 -> v0.53.0) ([#149](https://github.com/ppat/coder/issues/149)) ([42be84a](https://github.com/ppat/coder/commit/42be84a46676a985f3461d988b9a04cc7596d3ec))
* **cli-tools:** update wilfred/difftastic (0.58.0 -> 0.59.0) ([#126](https://github.com/ppat/coder/issues/126)) ([6c7ba0d](https://github.com/ppat/coder/commit/6c7ba0d6fa224db2ee5cdb3b2463ed680bb38385))
* **cli-tools:** update wilfred/difftastic (0.59.0 -> 0.60.0) ([#135](https://github.com/ppat/coder/issues/135)) ([77b8478](https://github.com/ppat/coder/commit/77b8478a8c5061cbeaffba47f7a282394e3af4bf))
* **galaxy-collection:** update galaxy-collection ([#132](https://github.com/ppat/coder/issues/132)) ([ba65beb](https://github.com/ppat/coder/commit/ba65bebe6ea0ee8f678da628452f1e4cf189ee97))
* **lang-sdk:** update node (v20.15.1 -> v20.16.0) ([#146](https://github.com/ppat/coder/issues/146)) ([a9a02b0](https://github.com/ppat/coder/commit/a9a02b0cc5c1deccb004df005600d4e21ea9b859))
* **lang-sdk:** update rust-lang/rust (1.79.0 -> 1.80.0) ([#150](https://github.com/ppat/coder/issues/150)) ([fdc3a9a](https://github.com/ppat/coder/commit/fdc3a9aede61e37a638281bc1c8b84aca392e06c))
* **npm-tools:** update renovate (37.413.5 -> 37.414.1) ([#121](https://github.com/ppat/coder/issues/121)) ([36eaba8](https://github.com/ppat/coder/commit/36eaba8cb46c8b9622b3037bb658c47dfff550e1))
* **npm-tools:** update renovate (37.414.1 -> 37.440.6) ([#127](https://github.com/ppat/coder/issues/127)) ([be2eb90](https://github.com/ppat/coder/commit/be2eb90db8fce4844554ef5cb581ebbc7beefb37))
* **pypi-tools:** update pre-commit (3.7.1 -> 3.8.0) ([#155](https://github.com/ppat/coder/issues/155)) ([90be31d](https://github.com/ppat/coder/commit/90be31d0880cd50e723bf2bfcee03194b8b32fc5))

### 🐛 Enhancements + Bug Fixes

* **cli-tools:** install critical cli-tools at image build time + rest at agent-startup ([#161](https://github.com/ppat/coder/issues/161)) ([452e01c](https://github.com/ppat/coder/commit/452e01c33bbb1a027212acea880d76bd1b807b9f))
* **cli-tools:** update dandavison/delta (0.18.0 -> 0.18.1) ([#153](https://github.com/ppat/coder/issues/153)) ([e49e62a](https://github.com/ppat/coder/commit/e49e62ae008627a7b1264102edbab453c381d272))
* **cli-tools:** update helm/helm (v3.15.3 -> v3.15.4) ([#140](https://github.com/ppat/coder/issues/140)) ([0f6781c](https://github.com/ppat/coder/commit/0f6781cefd2d10b5843bf3348d957701134a5ccc))
* **cli-tools:** update kubernetes/kubernetes (v1.30.2 -> v1.30.3) ([#120](https://github.com/ppat/coder/issues/120)) ([53854b7](https://github.com/ppat/coder/commit/53854b7394fd3a8dd85a8f6c8235deadd49c854a))
* **cli-tools:** update kubernetes/kubernetes (v1.30.3 -> v1.30.4) ([#141](https://github.com/ppat/coder/issues/141)) ([8066ad3](https://github.com/ppat/coder/commit/8066ad3c56b42c73795aeff352ec33d617e08293))
* **cli-tools:** update mikefarah/yq (v4.44.2 -> v4.44.3) ([#133](https://github.com/ppat/coder/issues/133)) ([937452f](https://github.com/ppat/coder/commit/937452fdf5a5a77445041f353044697d00360786))
* **cli-tools:** update nektos/act (v0.2.64 -> v0.2.65) ([#131](https://github.com/ppat/coder/issues/131)) ([2db844a](https://github.com/ppat/coder/commit/2db844ab2a72eb040f61b41fe6782d8710ddf011))
* **cli-tools:** update yannh/kubeconform (v0.6.6 -> v0.6.7) ([#130](https://github.com/ppat/coder/issues/130)) ([3d77dc8](https://github.com/ppat/coder/commit/3d77dc8281382b64886b3b274d0aeed10e945327))
* **lang-sdk:** update golang (1.22.5 -> 1.22.6) ([#138](https://github.com/ppat/coder/issues/138)) ([91ea8bb](https://github.com/ppat/coder/commit/91ea8bb5e24f57925ec74359ef6ff7726ddcdfce))
* **npm-tools:** update npm ([#117](https://github.com/ppat/coder/issues/117)) ([793d30d](https://github.com/ppat/coder/commit/793d30d2719a50ea99f6fa5149e495635a1f59d0))
* **pypi-tools:** update ansible-core (2.17.1 -> 2.17.2) ([#123](https://github.com/ppat/coder/issues/123)) ([0f7e6de](https://github.com/ppat/coder/commit/0f7e6de99b66977ebed601ac2ad571e6d8befabe))
* **pypi-tools:** update ansible-core (2.17.2 -> 2.17.3) ([#144](https://github.com/ppat/coder/issues/144)) ([1d9ed68](https://github.com/ppat/coder/commit/1d9ed68a8ca1dff101d99e1a5e29f330970f8374))

### 📌 Dependencies

* **deps:** update dependency renovate to v37.413.2 ([#103](https://github.com/ppat/coder/issues/103)) ([2664136](https://github.com/ppat/coder/commit/266413615920e4893b34f267c6b3a3fc4ecc6631))
* **deps:** update tj-actions/changed-files digest to 6b2903b ([#102](https://github.com/ppat/coder/issues/102)) ([1b2d0cf](https://github.com/ppat/coder/commit/1b2d0cff65529f84697c33dcfe80d77803032667))

## [1.7.6](https://github.com/ppat/coder/compare/v1.7.5...v1.7.6) (2024-07-19)

### 🐛 Enhancements + Bug Fixes

* extract out workspace template entrypoint into its own file ([#112](https://github.com/ppat/coder/issues/112)) ([9785eed](https://github.com/ppat/coder/commit/9785eede5bb80fe0e1d2e1a148cae7cf4170487b))

### 🛠 Improvements

* fix image test so that agent-startup script can be tested ([#111](https://github.com/ppat/coder/issues/111)) ([3b7749e](https://github.com/ppat/coder/commit/3b7749efd30c95eca2ad3e31788b286b61116aff))

## [1.7.5](https://github.com/ppat/coder/compare/v1.7.4...v1.7.5) (2024-07-19)

### 🐛 Enhancements + Bug Fixes

* fix user creation during workspace startup ([#110](https://github.com/ppat/coder/issues/110)) ([3c3f0ea](https://github.com/ppat/coder/commit/3c3f0ea03a0526d9f964ceba0ff5cd0ba7b03c39))

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
