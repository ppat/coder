// Commit taxonomy for this repo. The reasoning behind the vocabulary, and the decision procedure for
// picking a header, live in .claude/rules/commits.md - this file is only the enforcement.

// Scopes whose footprint reaches a consumer: the image container runtimes pull, or the template the Coder
// provisioner applies. The empty scope is here because an atomic change spanning both shipped trees has no
// single true scope, and must still be able to force a release.
const SHIPPED_SCOPES = ['', 'image', 'template']

// Types release-please renders, each of which forces a release of BOTH deliverables.
const RELEASE_FORCING_TYPES = ['feat', 'fix', 'perf', 'refactor', 'revert']

// Types release-please hides. A release window containing only these produces no release at all, so they
// must never carry a shipped scope - a real image or template change typed `chore` would silently never
// be published.
const HIDDEN_TYPES = ['build', 'chore', 'ci']

// A release rebuilds the image for two architectures and pushes the template to production. Both halves of
// this rule exist to keep "a release happened" and "a shipped artifact changed" the same statement.
const validateTypeScopePairing = async (parsedCommit) => {
  const { type, scope } = parsedCommit
  const normalizedScope = scope || ''

  if (RELEASE_FORCING_TYPES.includes(type) && !SHIPPED_SCOPES.includes(normalizedScope)) {
    return [
      false,
      `type '${type}' forces a release, so it requires a scope that ships (${SHIPPED_SCOPES.map((s) => s || '<empty>').join(', ')}), not '${normalizedScope || '<empty>'}'`,
    ]
  }

  if (HIDDEN_TYPES.includes(type) && SHIPPED_SCOPES.includes(normalizedScope) && normalizedScope !== '') {
    return [
      false,
      `type '${type}' is hidden from the changelog and cannot trigger a release, so it must not claim the shipped scope '${normalizedScope}'`,
    ]
  }

  return [true]
}

// Renovate's landed commits carry a `Co-authored-by:` trailer that GitHub appends at squash time and that
// exceeds the line limit on its own. commitlint classifies that trailer as body, not footer, so
// `footer-max-line-length` does not cover it. Exempting the line itself keeps the limit meaningful for
// hand-written prose while leaving every bot commit lintable - which matters because the PR title job and
// any future check on the landed commit both see the trailer.
const validateBodyMaxLengthIgnoringTrailers = async (parsedCommit) => {
  const { maxLineLength } = await import('@commitlint/ensure');

  const { body } = parsedCommit

  const bodyMaxLineLength = 120;
  const measurableBody = (body || '')
    .split('\n')
    .filter((line) => !/^Co-authored-by:\s/i.test(line))
    .join('\n')

  return [
    !measurableBody || maxLineLength(measurableBody, bodyMaxLineLength),
    `commit message body line length must not exceed ${bodyMaxLineLength}`,
  ]
}

module.exports = {
  extends: ['@commitlint/config-conventional'],
  plugins: ['commitlint-plugin-function-rules'],
  rules: {
    // increase max line length for header
    'header-max-length': [2, 'always', 120],

    // disable max line length for footers
    'footer-max-line-length': [0, 'always'],

    // disable default 'body-max-line-length' rule and add custom rule for body-max-line-length
    'body-max-line-length': [0],
    'function-rules/body-max-line-length': [
      2,
      'always',
      validateBodyMaxLengthIgnoringTrailers
    ],

    // specify the allowed scopes. ordering and footprints are in .claude/rules/commits.md; `github-actions`
    // and `internal-dependencies` are emitted by the shared Renovate presets, so this enum and the preset
    // pin have to move together.
    'scope-enum': [2, 'always',
      [
        '',
        'agents',
        'github-actions',
        'image',
        'internal-dependencies',
        'internal-workflows',
        'release',
        'renovate',
        'template'
      ]
    ],

    // a type may only sit on a scope that can carry its release claim
    'function-rules/type-enum': [
      2,
      'always',
      validateTypeScopePairing
    ],

    // don't validate case of body
    'body-case': [0, 'always']
  }
}
