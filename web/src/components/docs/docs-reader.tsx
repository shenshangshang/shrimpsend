'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { Components } from 'react-markdown';
import type { ComponentType, ReactNode } from 'react';
import { useMemo, useState } from 'react';
import { useI18n } from '@/contexts/I18nContext';
import { localizedDocsHref, parseDocsPathname, type LocalePath } from '@/lib/i18nRouting';
import { SiteFooter } from '@/components/landing/SiteFooter';
import { SiteNav } from '@/components/landing/SiteNav';
import { cn } from '@/lib/utils';
import { BookOpen, Mail, ScrollText, Settings2, ShieldCheck } from 'lucide-react';
import type { DocsDocId, DocsHeading, DocsMarkdownSource, DocsRegion, S3SectionId } from '@/lib/docsConfig';
import { s3SectionsForRegion } from '@/lib/docsConfig';
import { DocsCodeBlock } from '@/components/docs/docs-code-block';
import docsImageManifest from '@/lib/docsImageManifest.json';

type DocsImageManifest = Record<string, { width: number; height: number }>;

const docImageSizes = docsImageManifest as DocsImageManifest;

const docImageClassName =
  'mx-auto block h-auto w-auto max-w-[min(100%,42rem)] rounded-xl border border-border bg-muted object-contain shadow-sm';

function DocsMarkdownImage({ src, alt, ...props }: React.ComponentProps<'img'>) {
  const srcStr = typeof src === 'string' ? src : undefined;
  const isDocPng = Boolean(srcStr?.startsWith('/docs/') && /\.png$/i.test(srcStr));
  const webpSrc = isDocPng && srcStr ? srcStr.replace(/\.png$/i, '.webp') : undefined;
  const dimensions = srcStr ? docImageSizes[srcStr] : undefined;

  const img = (
    /* eslint-disable-next-line @next/next/no-img-element */
    <img
      src={srcStr}
      alt={alt ?? ''}
      className={docImageClassName}
      loading="lazy"
      width={dimensions?.width}
      height={dimensions?.height}
      {...props}
    />
  );

  return (
    <figure className="my-6 flex flex-col items-center">
      {webpSrc ? (
        <picture>
          <source type="image/webp" srcSet={webpSrc} />
          {img}
        </picture>
      ) : (
        img
      )}
      {alt ? (
        <figcaption className="mt-2 text-center text-xs leading-5 text-muted-foreground">{alt}</figcaption>
      ) : null}
    </figure>
  );
}

const docItems: Array<{ id: DocsDocId; labelKey: string; icon: ComponentType<{ className?: string; size?: number }> }> = [
  { id: 'intro', labelKey: 'docs.nav.intro', icon: BookOpen },
  { id: 's3', labelKey: 'docs.nav.s3', icon: Settings2 },
  { id: 'privacy', labelKey: 'docs.nav.privacy', icon: ShieldCheck },
  { id: 'terms', labelKey: 'docs.nav.terms', icon: ScrollText },
  { id: 'contact', labelKey: 'docs.nav.contact', icon: Mail },
];

const s3SectionLabelKeys: Record<S3SectionId, string> = {
  overview: 'docs.nav.s3Overview',
  bitiful: 'docs.nav.s3Bitiful',
  'data-capsule': 'docs.nav.s3DataCapsule',
  'built-in': 'docs.nav.s3BuiltIn',
  'tencent-cos': 'docs.nav.s3TencentCos',
  'cloudflare-r2': 'docs.nav.s3CloudflareR2',
  rustfs: 'docs.nav.s3Rustfs',
};

function headingText(children: ReactNode): string {
  if (typeof children === 'string') return children;
  if (Array.isArray(children)) return children.map(headingText).join('');
  if (children && typeof children === 'object' && 'props' in children) {
    return headingText((children as { props?: { children?: ReactNode } }).props?.children);
  }
  return '';
}

function slugifyHeading(input: string): string {
  const base = input
    .replace(/[`*_~[\]()]/g, '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^\p{Letter}\p{Number}-]+/gu, '');
  return base || 'section';
}

function paragraphIsImageOnly(node: unknown): boolean {
  const p = node as { tagName?: string; children?: Array<{ type?: string; tagName?: string; value?: string }> } | undefined;
  if (p?.tagName !== 'p' || !p.children) return false;
  const meaningful = p.children.filter(
    (child) => child.type !== 'text' || (child.value?.trim() ?? '') !== '',
  );
  return meaningful.length === 1 && meaningful[0]?.type === 'element' && meaningful[0]?.tagName === 'img';
}

const markdownComponents: Components = {
  h1: ({ children, ...props }) => (
    <h1 className="mb-5 scroll-mt-24 text-[26px] font-semibold tracking-tight text-foreground" {...props}>
      {children}
    </h1>
  ),
  h2: ({ children, ...props }) => (
    <h2 id={slugifyHeading(headingText(children))} className="mb-3 mt-9 scroll-mt-24 text-xl font-semibold tracking-tight text-foreground" {...props}>
      {children}
    </h2>
  ),
  h3: ({ children, ...props }) => (
    <h3 id={slugifyHeading(headingText(children))} className="mb-2 mt-7 scroll-mt-24 text-lg font-semibold text-foreground" {...props}>
      {children}
    </h3>
  ),
  p: ({ children, node, ...props }) => {
    if (paragraphIsImageOnly(node)) {
      return <div className="mb-4">{children}</div>;
    }
    return (
      <p className="mb-4 text-sm leading-7 text-foreground/88" {...props}>
        {children}
      </p>
    );
  },
  ul: ({ children, ...props }) => (
    <ul className="mb-4 list-disc space-y-1.5 pl-5 text-sm leading-7 text-foreground/88" {...props}>
      {children}
    </ul>
  ),
  ol: ({ children, ...props }) => (
    <ol className="mb-4 list-decimal space-y-1.5 pl-5 text-sm leading-7 text-foreground/88" {...props}>
      {children}
    </ol>
  ),
  li: ({ children, ...props }) => (
    <li className="marker:text-primary/70" {...props}>
      {children}
    </li>
  ),
  a: ({ children, href, ...props }) => (
    <a
      href={href}
      className="font-semibold text-[var(--docs-link)] underline decoration-[var(--docs-link-decoration)] underline-offset-4 transition-colors hover:text-[var(--docs-link-hover)] hover:decoration-[var(--docs-link-hover)]"
      rel="noopener noreferrer"
      {...props}
    >
      {children}
    </a>
  ),
  blockquote: ({ children, ...props }) => (
    <blockquote className="mb-4 rounded-xl border border-primary/20 bg-primary/[0.08] px-4 py-3 text-sm text-muted-foreground" {...props}>
      {children}
    </blockquote>
  ),
  hr: (props) => <hr className="my-8 border-border" {...props} />,
  table: ({ children, ...props }) => (
    <div className="mb-4 overflow-x-auto rounded-xl border border-border">
      <table className="w-full min-w-[560px] border-collapse text-left text-sm" {...props}>
        {children}
      </table>
    </div>
  ),
  thead: ({ children, ...props }) => <thead className="bg-muted text-foreground" {...props}>{children}</thead>,
  th: ({ children, ...props }) => (
    <th className="border-b border-border px-3 py-2 font-semibold" {...props}>
      {children}
    </th>
  ),
  td: ({ children, ...props }) => (
    <td className="border-b border-border px-3 py-2 align-top text-foreground/88" {...props}>
      {children}
    </td>
  ),
  tr: ({ children, ...props }) => <tr className="last:[&>td]:border-b-0" {...props}>{children}</tr>,
  code: ({ className, children, ...props }) => {
    const isFenced = Boolean(className?.startsWith('language-'));
    if (isFenced) return <code className={className} {...props}>{children}</code>;
    return <code className="rounded bg-muted px-1 py-0.5 font-mono text-[0.85em]" {...props}>{children}</code>;
  },
  pre: ({ children, ...props }) => (
    <DocsCodeBlock {...props}>{children}</DocsCodeBlock>
  ),
  strong: ({ children, ...props }) => <strong className="font-semibold text-foreground" {...props}>{children}</strong>,
  img: DocsMarkdownImage,
};

export function DocsReader({
  doc,
  initialDoc,
  initialS3Section,
  localePath,
  region,
}: {
  doc: DocsMarkdownSource;
  initialDoc: DocsDocId;
  initialS3Section?: S3SectionId;
  localePath: LocalePath;
  region: DocsRegion;
}) {
  const { t, localeTag } = useI18n();
  const zh = localeTag.startsWith('zh');
  const [query, setQuery] = useState('');
  const pathname = usePathname();
  const routeFromPath = useMemo(() => parseDocsPathname(pathname), [pathname]);
  const activeDoc = routeFromPath?.doc ?? initialDoc;
  const activeS3Section = routeFromPath?.s3Section ?? initialS3Section ?? doc.section;
  const activeItem = docItems.find((item) => item.id === activeDoc) ?? docItems[0]!;
  const s3Sections = useMemo(() => s3SectionsForRegion(region), [region]);
  const isS3Active = activeDoc === 's3';

  const headings = useMemo<DocsHeading[]>(() => doc.headings, [doc]);

  const badgeLabel = isS3Active && activeS3Section
    ? `${t(activeItem.labelKey)} · ${t(s3SectionLabelKeys[activeS3Section])}`
    : t(activeItem.labelKey);

  const visibleItems = docItems.filter(item => !query || t(item.labelKey).toLowerCase().includes(query.toLowerCase()) || item.id === activeDoc);
  const visibleHeadings = headings.filter(item => !query || item.title.toLowerCase().includes(query.toLowerCase()));
  return <div className="public-site">
    <SiteNav active="docs" />
    <main className="public-docs">
      <aside className="public-docs-sidebar"><div>
        <h2>{zh ? '使用文档' : 'Documentation'}</h2>
        <input type="search" aria-label={zh ? '搜索文档目录' : 'Search documentation headings'} placeholder={zh ? '搜索文档目录' : 'Search headings'} value={query} onChange={e => setQuery(e.target.value)} />
        <nav aria-label={t('docs.nav.label')}>
          {visibleItems.map(({id,labelKey,icon:Icon})=><div key={id}>
            <Link href={localizedDocsHref(localePath,id)} aria-current={activeDoc===id?'page':undefined}><Icon size={16}/>{t(labelKey)}</Link>
            {id==='s3' && isS3Active && <div className="docs-subnav">{s3Sections.map(sectionId=><Link key={sectionId} href={localizedDocsHref(localePath,'s3',sectionId)} aria-current={activeS3Section===sectionId?'page':undefined}>{t(s3SectionLabelKeys[sectionId])}</Link>)}</div>}
            {id===activeDoc && !isS3Active && <div className="docs-subnav">{visibleHeadings.filter(h=>h.depth===2).map(h=><a key={h.id} href={`#${h.id}`}>{h.title}</a>)}</div>}
          </div>)}
        </nav>
        {query && visibleHeadings.length===0 && <p className="text-xs text-muted-foreground p-3">{zh?'当前文档没有匹配的章节':'No matching sections in this document.'}</p>}
      </div></aside>
      <article className="docs-markdown">
        <div className="docs-breadcrumb">{zh?'使用文档':'Documentation'} / <span>{badgeLabel}</span></div>
        {isS3Active && <nav className="flex gap-2 overflow-x-auto mb-5 lg:hidden" aria-label="S3">{s3Sections.map(id=><Link className="shrink-0 rounded-lg px-3 py-2 text-xs bg-muted" key={id} href={localizedDocsHref(localePath,'s3',id)}>{t(s3SectionLabelKeys[id])}</Link>)}</nav>}
        <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>{doc.source}</ReactMarkdown>
      </article>
      <aside className="public-docs-toc"><div><h2>{t('docs.index.title')}</h2>{visibleHeadings.map(h=><a key={h.id} href={`#${h.id}`} className={cn(h.depth===3&&'nested')}>{h.title}</a>)}</div></aside>
    </main>
    <SiteFooter/>
  </div>;
}
