import React, { useMemo, useState } from 'react';
import { Check, Copy, Download, FileCode2, FolderArchive, Terminal } from 'lucide-react';
import { AgentSpurLogo } from './components/AgentSpurLogo';
import { buildMacOSZipBlob, ZipFileEntry } from './utils/zipBuilder';

import packageSwiftRaw from '../Package.swift?raw';
import buildDmgShRaw from '../build_dmg.sh?raw';
import doubleClickCmdRaw from '../双击打包DMG.command?raw';
import makefileRaw from '../Makefile?raw';
import readmeRaw from '../README.md?raw';
import infoPlistRaw from '../Resources/Info.plist?raw';
import samplePackJsonRaw from '../Resources/sample-deepseek-pack.json?raw';
import appEntrySwiftRaw from '../Sources/AgentSpur/AgentSpurApp.swift?raw';
import pricingEngineSwiftRaw from '../Sources/AgentSpur/DeepSeekPricingEngine.swift?raw';
import modelsSwiftRaw from '../Sources/AgentSpur/Models.swift?raw';
import dbReaderSwiftRaw from '../Sources/AgentSpur/OpenCodeDBReader.swift?raw';
import spriteRendererSwiftRaw from '../Sources/AgentSpur/SpriteRenderer.swift?raw';
import terminalBridgeSwiftRaw from '../Sources/AgentSpur/TerminalBridge.swift?raw';
import popoverViewsSwiftRaw from '../Sources/AgentSpur/PopoverViews.swift?raw';

interface SourceFileItem {
  relPath: string;
  label: string;
  content: string;
  executable?: boolean;
}

const NATIVE_FILES: SourceFileItem[] = [
  {
    relPath: 'build_dmg.sh',
    label: 'build_dmg.sh (一键生成 DMG)',
    content: buildDmgShRaw,
    executable: true,
  },
  {
    relPath: '双击打包DMG.command',
    label: '双击打包DMG.command',
    content: doubleClickCmdRaw,
    executable: true,
  },
  {
    relPath: 'Package.swift',
    label: 'Package.swift',
    content: packageSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/AgentSpurApp.swift',
    label: 'Sources/AgentSpur/AgentSpurApp.swift',
    content: appEntrySwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/DeepSeekPricingEngine.swift',
    label: 'Sources/AgentSpur/DeepSeekPricingEngine.swift (汇率+阶梯计费+CSV)',
    content: pricingEngineSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/PopoverViews.swift',
    label: 'Sources/AgentSpur/PopoverViews.swift',
    content: popoverViewsSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/OpenCodeDBReader.swift',
    label: 'Sources/AgentSpur/OpenCodeDBReader.swift',
    content: dbReaderSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/SpriteRenderer.swift',
    label: 'Sources/AgentSpur/SpriteRenderer.swift',
    content: spriteRendererSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/TerminalBridge.swift',
    label: 'Sources/AgentSpur/TerminalBridge.swift',
    content: terminalBridgeSwiftRaw,
  },
  {
    relPath: 'Sources/AgentSpur/Models.swift',
    label: 'Sources/AgentSpur/Models.swift',
    content: modelsSwiftRaw,
  },
  {
    relPath: 'Resources/Info.plist',
    label: 'Resources/Info.plist',
    content: infoPlistRaw,
  },
  {
    relPath: 'Resources/sample-deepseek-pack.json',
    label: 'Resources/sample-deepseek-pack.json',
    content: samplePackJsonRaw,
  },
  {
    relPath: 'Makefile',
    label: 'Makefile',
    content: makefileRaw,
  },
  {
    relPath: 'README.md',
    label: 'README.md',
    content: readmeRaw,
  },
];

export default function App() {
  const [selectedPath, setSelectedPath] = useState<string>('build_dmg.sh');
  const [copiedCmd, setCopiedCmd] = useState<boolean>(false);
  const [copiedFile, setCopiedFile] = useState<boolean>(false);

  const selectedFile = useMemo(
    () => NATIVE_FILES.find((f) => f.relPath === selectedPath) ?? NATIVE_FILES[0],
    [selectedPath]
  );

  const handleDownloadNativeZip = () => {
    const entries: ZipFileEntry[] = NATIVE_FILES.map((f) => ({
      path: `AgentSpur/${f.relPath}`,
      content: f.content,
      executable: f.executable,
    }));
    const blob = buildMacOSZipBlob(entries);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'AgentSpur-macOS-Native.zip';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleCopyCommand = async () => {
    try {
      await navigator.clipboard.writeText('chmod +x build_dmg.sh && ./build_dmg.sh');
      setCopiedCmd(true);
      window.setTimeout(() => setCopiedCmd(false), 1600);
    } catch {
      // Ignore clipboard fallback
    }
  };

  const handleCopyCurrentFile = async () => {
    try {
      await navigator.clipboard.writeText(selectedFile.content);
      setCopiedFile(true);
      window.setTimeout(() => setCopiedFile(false), 1600);
    } catch {
      // Ignore clipboard fallback
    }
  };

  return (
    <div className="min-h-screen w-full bg-gradient-to-br from-white via-[#F8FAFC] to-sky-50/50 text-slate-900">
      <header className="sticky top-0 z-30 border-b border-slate-200/70 bg-white/80 backdrop-blur-2xl">
        <div className="mx-auto flex h-14 max-w-[1160px] items-center justify-between gap-4 px-6">
          <div className="flex items-center gap-2.5">
            <AgentSpurLogo size={24} />
            <span className="text-sm font-semibold tracking-tight text-slate-900">
              AgentSpur
            </span>
            <span className="text-slate-300" aria-hidden="true">
              ·
            </span>
            <span className="text-xs text-slate-500">
              纯原生 macOS AppKit 菜单栏工程 (无任何 Web 依赖)
            </span>
          </div>

          <button
            type="button"
            onClick={handleDownloadNativeZip}
            className="inline-flex items-center gap-2 rounded-xl border border-sky-300/70 bg-sky-500/[0.11] px-4 py-2 text-xs font-semibold text-sky-800 shadow-[0_1px_2px_rgba(14,165,233,0.08)] hover:bg-sky-500/[0.18] hover:border-sky-400/70 transition-all cursor-pointer whitespace-nowrap shrink-0"
          >
            <FolderArchive className="w-4 h-4 text-sky-600 shrink-0" />
            <span>下载纯 macOS 原生源码包 (.zip)</span>
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-[1160px] space-y-8 px-6 py-10">
        {/* Hero & One-Command DMG Packaging Flow */}
        <section className="rounded-2xl border border-slate-200/75 bg-white/85 p-8 shadow-[0_20px_50px_-18px_rgba(15,23,42,0.07)] backdrop-blur-2xl space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="space-y-2 max-w-2xl">
              <div className="flex items-center gap-2 text-xs text-slate-500 font-mono">
                <span>macOS 14.0+</span>
                <span aria-hidden="true">·</span>
                <span>AppKit + SQLite3 + FSEvents</span>
                <span aria-hidden="true">·</span>
                <span>LSUIElement 纯菜单栏</span>
              </div>
              <h1 className="text-2xl font-semibold tracking-tight text-slate-900 text-balance">
                下载源码后在 Mac 上一键打包生成 AgentSpur.dmg
              </h1>
              <p className="text-sm leading-relaxed text-slate-600">
                点击右上角下载 <code className="font-mono text-xs text-sky-700">AgentSpur-macOS-Native.zip</code>（仅包含纯净 Swift 原生源码、Info.plist 与 DMG 打包脚本，已剔除全部前端文件），在 Mac 上解压后直接双击{' '}
                <code className="font-mono text-xs text-slate-800">双击打包DMG.command</code> 或执行下方命令，即可自动生成带专属冰瓷图标与拖拽安装入口的{' '}
                <code className="font-mono text-xs text-slate-800">AgentSpur.dmg</code>。
              </p>
            </div>

            <div className="shrink-0">
              <button
                type="button"
                onClick={handleDownloadNativeZip}
                className="inline-flex items-center gap-2 rounded-xl border border-sky-300/75 bg-sky-500/[0.12] px-5 py-3 text-sm font-semibold text-sky-800 shadow-[0_2px_8px_rgba(14,165,233,0.10)] hover:bg-sky-500/[0.18] hover:border-sky-400/80 transition-all cursor-pointer whitespace-nowrap"
              >
                <Download className="w-4 h-4 text-sky-600 shrink-0" />
                <span>一键下载 AgentSpur-macOS-Native.zip</span>
              </button>
            </div>
          </div>

          <div className="pt-4 border-t border-slate-200/70 grid grid-cols-1 md:grid-cols-3 gap-6 text-xs">
            <div className="space-y-1.5">
              <div className="font-semibold text-slate-800">01. 解压纯净原生包</div>
              <p className="text-slate-500 leading-relaxed">
                解压得到 <code className="font-mono">AgentSpur/</code> 目录（内含 <code className="font-mono">Package.swift</code>、<code className="font-mono">Sources/</code>、<code className="font-mono">Resources/Info.plist</code> 与打包脚本，已预设可执行权限）。
              </p>
            </div>
            <div className="space-y-1.5">
              <div className="font-semibold text-slate-800">02. 双击或一行命令构建</div>
              <p className="text-slate-500 leading-relaxed">
                在访达中直接双击 <code className="font-mono">双击打包DMG.command</code>，或在终端执行下方脚本，自动编译 Release 二进制、合成 <code className="font-mono">.icns</code> 图标并完成本地签名。
              </p>
            </div>
            <div className="space-y-1.5">
              <div className="font-semibold text-slate-800">03. 拖入 Applications 使用</div>
              <p className="text-slate-500 leading-relaxed">
                自动弹出生成的 <code className="font-mono">AgentSpur.dmg</code>，打开后拖入 <code className="font-mono">Applications</code> 即可在顶部状态栏只读监听本机 <code className="font-mono">opencode.db</code>。
              </p>
            </div>
          </div>

          <div className="flex items-center justify-between gap-3 rounded-xl border border-slate-200/80 bg-slate-50/90 px-4 py-3 font-mono text-xs text-slate-800">
            <div className="flex items-center gap-2.5 min-w-0 truncate">
              <Terminal className="w-4 h-4 text-sky-600 shrink-0" />
              <span className="truncate">cd AgentSpur && chmod +x build_dmg.sh && ./build_dmg.sh</span>
            </div>
            <button
              type="button"
              onClick={handleCopyCommand}
              className="inline-flex items-center gap-1 rounded-lg border border-slate-200/85 bg-white px-2.5 py-1 text-[11px] font-sans font-medium text-slate-600 hover:text-slate-900 hover:border-slate-300 transition-all shrink-0 cursor-pointer"
            >
              {copiedCmd ? (
                <>
                  <Check className="w-3.5 h-3.5 text-sky-600" />
                  <span>已复制命令</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>复制命令</span>
                </>
              )}
            </button>
          </div>
        </section>

        {/* Native Swift & DMG Packaging Source Code Browser */}
        <section className="rounded-2xl border border-slate-200/75 bg-white/85 shadow-[0_20px_50px_-18px_rgba(15,23,42,0.06)] backdrop-blur-2xl overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200/70 px-6 py-3.5">
            <div className="flex items-center gap-2 text-xs font-semibold text-slate-800">
              <FileCode2 className="w-4 h-4 text-sky-600 shrink-0" />
              <span>macOS 原生工程文件一览 ({NATIVE_FILES.length} 个文件)</span>
            </div>

            <button
              type="button"
              onClick={handleCopyCurrentFile}
              className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200/85 bg-white/90 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-white hover:text-slate-900 hover:border-slate-300 transition-all cursor-pointer whitespace-nowrap shrink-0"
            >
              {copiedFile ? (
                <>
                  <Check className="w-3.5 h-3.5 text-sky-600" />
                  <span>已复制 {selectedFile.relPath}</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5" />
                  <span>复制当前文件</span>
                </>
              )}
            </button>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 min-h-[480px]">
            <aside className="lg:col-span-4 border-b lg:border-b-0 lg:border-r border-slate-200/70 p-3 space-y-1 bg-slate-50/50">
              {NATIVE_FILES.map((item) => {
                const active = item.relPath === selectedFile.relPath;
                return (
                  <button
                    key={item.relPath}
                    type="button"
                    onClick={() => setSelectedPath(item.relPath)}
                    className={`w-full text-left rounded-xl px-3 py-2 text-xs font-mono transition-all cursor-pointer truncate ${
                      active
                        ? 'bg-sky-500/[0.11] text-sky-900 font-semibold border border-sky-300/60'
                        : 'border border-transparent text-slate-600 hover:bg-white/80 hover:text-slate-900'
                    }`}
                  >
                    {item.label}
                  </button>
                );
              })}
            </aside>

            <div className="lg:col-span-8 p-5 overflow-auto max-h-[560px] bg-white/60">
              <pre className="text-xs font-mono leading-relaxed text-slate-800 whitespace-pre">
                <code>{selectedFile.content}</code>
              </pre>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
