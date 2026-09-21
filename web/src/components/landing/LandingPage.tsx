'use client';

import Link from 'next/link';
import Image from 'next/image';
import { useEffect, useState } from 'react';
import { ArrowRight, Download, Folder, Laptop, Monitor, RefreshCw, Smartphone, UserRound, Check, ChevronDown } from 'lucide-react';
import { useI18n } from '@/contexts/I18nContext';
import { getClientReleaseDownloadUrl, isClientDownloadOverseas } from '@/lib/clientReleaseDownload';
import { getApiUrl } from '@/lib/config';
import { SiteFooter } from './SiteFooter';
import { SiteNav } from './SiteNav';
import { buttonVariants } from '@/components/ui/button';
import type { LocalePath } from '@/lib/i18nRouting';
import { SITE_NAME, absoluteUrl } from '@/lib/seo';

type DownloadRegion = {macUrl?: string;winUrl?: string;apkUrl?: string;iosStoreUrl?: string;googlePlayUrl?: string;appStoreUrl?: string};
type Downloads = {available: boolean;version?: string;mainland?: DownloadRegion;overseas?: DownloadRegion};
function validDownload(value?: string) { try { const u = new URL(value || ''); return ['https:', 'http:'].includes(u.protocol) ? u.href : undefined; } catch { return undefined; } }

export function LandingPage({localePath, siteOrigin}: {localePath: LocalePath;siteOrigin: string}) {
  const {localeTag} = useI18n();
  const zh = localeTag.startsWith('zh');
  const [downloads, setDownloads] = useState<Downloads>();
  const [platform, setPlatform] = useState('macOS');
  const releaseHref = getClientReleaseDownloadUrl({siteOrigin});
  const overseas = isClientDownloadOverseas({siteOrigin});
  const region = downloads?.available ? (overseas ? downloads.overseas : downloads.mainland) : undefined;
  useEffect(() => {
    const controller = new AbortController();
    const agent = navigator.userAgent;
    queueMicrotask(() => { if (controller.signal.aborted) return; setPlatform(/Android/i.test(agent) ? 'Android' : /iPhone|iPad/i.test(agent) ? 'iOS' : /Windows/i.test(agent) ? 'Windows' : /Linux/i.test(agent) ? 'Linux' : 'macOS'); });
    fetch(`${getApiUrl()}/api/app/public-download`, {signal: controller.signal}).then(r => r.ok ? r.json() : undefined).then(setDownloads).catch(() => {});
    return () => controller.abort();
  }, []);
  const platforms = [
    {name:'Windows',icon:Monitor,url:region?.winUrl}, {name:'macOS',icon:Laptop,url:region?.macUrl},
    {name:'Android',icon:Smartphone,url:region?.googlePlayUrl || region?.apkUrl}, {name:'iOS',icon:Smartphone,url:region?.appStoreUrl || region?.iosStoreUrl},
    {name:'Linux',icon:Monitor,url:undefined},
  ];
  const mainDownload = validDownload(platforms.find(p => p.name === platform)?.url) || releaseHref;
  const features = [
    {icon:UserRound,title:zh?'免登录使用':'No account needed',body:zh?'安装后即可使用。在本地网络中，让设备直接连接。':'Open the app and connect your devices directly on your local network.'},
    {icon:RefreshCw,title:zh?'断点续传':'Pick up where you left off',body:zh?'连接恢复后接着传，大文件也能安心发送。':'Resume interrupted transfers when your connection returns.'},
    {icon:Folder,title:zh?'文件直接保存':'Save straight to your folder',body:zh?'接收的文件直接保存到下载目录，或你选择的位置。':'Receive files in Downloads, or a folder you choose.'},
  ];
  const faqs = [
    [zh?'每台设备都需要登录吗？':'Does every device need an account?',zh?'不需要。设备可以独立使用。购买会员时登录一个账号，在其他设备输入授权码或扫码，再由购买者确认授权。':'No. Devices work independently. Sign in once to buy a membership, then authorize other devices with a code or QR scan and confirm them from the purchasing account.'],
    [zh?'没有互联网也可以传输吗？':'Can I transfer without internet?',zh?'可以。客户端在同一局域网中可以直接传输。浏览器需先打开网页；局域网访问能力还取决于浏览器权限和网络环境。':'Yes. Installed clients can transfer over the same local network. Open the web app beforehand; local network access also depends on browser permissions and the network.' ],
    [zh?'文件保存在哪里？':'Where do my files go?',zh?'客户端默认保存到系统下载目录，也可以自定义。支持目录授权的浏览器可以直接写入指定文件夹；其他浏览器遵循自身的下载设置。':'The app uses your system Downloads folder by default. Supported browsers can write directly to a folder you approve; other browsers use their download settings.' ],
    [zh?'两台设备不能直接连通怎么办？':'What if devices cannot connect directly?',zh?'应用会尝试可用的连接方式。单向网络可以使用接收端可达地址；需要中转时，可在连接设置中配置对象存储。':'The app tries available connections. A reachable receiving address can help with one-way networks. Configure object storage in connection settings when a relay is needed.' ],
  ];
  const schema = {'@context':'https://schema.org','@type':'SoftwareApplication',name:SITE_NAME[localePath],applicationCategory:'UtilitiesApplication',operatingSystem:'macOS, Windows, Linux, Android, iOS, Web',url:absoluteUrl(`/${localePath}`,siteOrigin),offers:{'@type':'Offer',price:'0',priceCurrency:zh?'CNY':'USD'}};
  return <div className="public-site">
    <script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(schema).replace(/</g,'\\u003c')}} />
    <SiteNav active="home" />
    <main className="public-main">
      <section className="public-hero" id="features">
        <div className="public-hero-copy">
          <h1>{zh?<>设备之间，<br/>轻松传递。</>:<>Your devices.<br/>Simply connected.</>}</h1>
          <p>{zh?<>文件和文字，打开就能传。<br/>支持免登录使用，也能在离线网络中互传。</>:<>Files and words, ready to go.<br/>No account needed. Local transfers work offline.</>}</p>
          <div className="flex flex-wrap gap-3">
            <a className={buttonVariants({size:'lg'})} href={mainDownload} target="_blank" rel="noopener noreferrer"><Download size={18}/>{zh?`下载 ${platform} 版`:`Get for ${platform}`}</a>
            <Link className={buttonVariants({variant:'outline',size:'lg'})} href="/chat">{zh?'打开网页版':'Open web app'}</Link>
          </div>
          <div className="public-platforms">{platforms.map(({name,icon:Icon})=><a key={name} href="#download"><Icon size={14}/>{name}</a>)}</div>
        </div>
        <Link href="/chat" className="public-product-shot" aria-label={zh?'打开虾传网页版':'Open ShrimpSend'}>
          <Image src="/product-preview.png" alt={zh?'虾传桌面界面：设备列表与文件传输会话':'ShrimpSend desktop: devices and a file transfer conversation'} width={1440} height={960} priority unoptimized/>
        </Link>
      </section>
      <section className="public-feature-row">{features.map(({icon:Icon,title,body})=><article key={title}><Icon size={27} strokeWidth={1.5}/><div><h2>{title}</h2><p>{body}</p></div></article>)}</section>
      <section className="public-section">
        <h2>{zh?'连接设备，选好文件，开始传输。':'Connect. Choose a file. Send.'}</h2>
        <div className="public-steps">{[
          [zh?'打开另一台设备上的虾传':'Open ShrimpSend on another device',zh?'在电脑或手机上打开应用，无需登录。':'Open the app on your computer or phone. No sign-in required.'],
          [zh?'选择对方设备':'Choose your device',zh?'选择附近设备，或使用连接码与二维码配对。':'Choose a nearby device, or pair with a connection code or QR.'],
          [zh?'选中文件并开始传输':'Choose files and send',zh?'拖入文件或输入文字，点发送即可。':'Drop in files or type a message, then press Send.'],
        ].map(([title,body],i)=><article key={title}><span>{i+1}</span><div><h3>{title}</h3><p>{body}</p></div></article>)}</div>
        <Link href={`/${localePath}/docs/intro`} className="inline-flex items-center gap-2 text-sm text-primary mt-7">{zh?'查看快速开始指南':'Read the getting started guide'}<ArrowRight size={16}/></Link>
      </section>
      <section className="public-section" id="download">
        <div className="public-section-title"><div><h2>{zh?'在你的设备上使用':'Make yourself at home'}</h2><p>{zh?'选择适合你的版本。各设备可以独立使用。':'Choose your platform. Every device works independently.'}</p></div>{downloads?.available&&downloads.version&&<span className="text-sm text-muted-foreground">v{downloads.version}</span>}</div>
        <div className="public-downloads">{platforms.map(({name,icon:Icon,url})=><a key={name} href={validDownload(url)||releaseHref} target="_blank" rel="noopener noreferrer"><Icon size={25} strokeWidth={1.5}/><strong>{name}</strong><span>{validDownload(url)?(zh?'下载客户端':'Download app'):(zh?'选择安装包':'Choose a package')}<ArrowRight size={14}/></span></a>)}</div>
      </section>
      <section className="public-section" id="pricing">
        <div className="public-section-title"><div><h2>{zh?'一个账号，授权多台设备。':'One account. Your authorized devices.'}</h2><p>{zh?'账号用来管理会员，传输始终以设备为中心。':'Manage your membership in one place. Keep transfers on your devices.'}</p></div></div>
        <div className="public-plans"><article><h3>{zh?'直接开始使用':'Start right away'}</h3><p>{zh?'日常传输无需创建账号。':'Everyday transfers without creating an account.'}</p><ul>{[zh?'局域网直接传输':'Direct local transfers',zh?'发送文件与文字':'Send files and text',zh?'自定义接收目录':'Choose your receive folder'].map(x=><li key={x}><Check size={16}/>{x}</li>)}</ul><Link href="/chat" className={buttonVariants({variant:'outline'})}>{zh?'打开网页版':'Open web app'}</Link></article><article><h3>{zh?'为设备开通会员':'Authorize your devices'}</h3><p>{zh?'购买设备名额后，按需分配与收回。':'Purchase device slots, then assign or release them as needed.'}</p><ul>{[zh?'已授权设备享受无限制信令服务':'Unlimited signaling for authorized devices',zh?'六位授权码或扫码授权':'Authorize with a six-character code or QR',zh?'其他设备无需登录购买账号':'Other devices stay signed out'].map(x=><li key={x}><Check size={16}/>{x}</li>)}</ul><Link href="/settings/membership" className={buttonVariants()}>{zh?'查看套餐与名额':'View plans and device slots'}</Link></article></div>
      </section>
      <section className="public-section public-faq" id="faq"><h2>{zh?'你可能想知道':'A few things to know'}</h2>{faqs.map(([q,a])=><details key={q}><summary>{q}<ChevronDown size={17}/></summary><p>{a}</p></details>)}</section>
    </main>
    <SiteFooter/>
  </div>;
}
