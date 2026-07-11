// @ts-check
/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Strip',
  tagline: 'Trust and evidence OS for computational aerospace',
  favicon: 'img/favicon.svg',
  url: 'https://smc17.github.io',
  baseUrl: '/strip/',
  organizationName: 'SMC17',
  projectName: 'strip',
  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',
  i18n: { defaultLocale: 'en', locales: ['en'] },
  markdown: {
    mermaid: true,
  },
  themes: ['@docusaurus/theme-mermaid'],
  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
          editUrl: 'https://github.com/SMC17/strip/tree/main/website/',
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      }),
    ],
  ],
  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      colorMode: { defaultMode: 'light', respectPrefersColorScheme: true },
      navbar: {
        title: 'Strip',
        items: [
          { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
          { href: 'https://github.com/SMC17/strip', label: 'GitHub', position: 'right' },
          { href: 'https://github.com/SMC17/strip/blob/main/ROADMAP-1.0.md', label: 'Roadmap', position: 'right' },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Programme',
            items: [
              { label: 'Status', href: 'https://github.com/SMC17/strip/blob/main/STATUS.md' },
              { label: 'Category', href: 'https://github.com/SMC17/strip/blob/main/docs/CATEGORY.md' },
              { label: 'Experimental', href: 'https://github.com/SMC17/strip/blob/main/EXPERIMENTAL.md' },
            ],
          },
          {
            title: 'Build',
            items: [
              { label: 'Reproducible Linux', to: '/reproducible-build' },
              { label: 'LICENSE', href: 'https://github.com/SMC17/strip/blob/main/LICENSE' },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} Strip contributors. Apache-2.0.`,
      },
    }),
};

export default config;
