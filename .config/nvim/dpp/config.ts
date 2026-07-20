// dpp.vim config.ts — evaluated by Deno only inside dpp#make_state(), never at
// Neovim runtime. It builds the plugin list (TOML -> lazy conversion) that
// gets baked into startup.vim/state.vim by dpp.vim itself (see init.lua).
// dpp.vim の config.ts — Deno上で dpp#make_state() 実行時にのみ評価される
// (Neovim実行時には走らない)。TOMLロード→lazy変換した結果を dpp.vim が
// startup.vim/state.vim へ焼き込む(呼び出し元は init.lua を参照)。
//
// NOTE: BaseConfig is imported dynamically from $NVIM_DPP_VIM (a Nix store
// path, see nix/modules/neovim.nix) instead of a static "jsr:@shougo/dpp-vim"
// specifier. This keeps state generation from depending on network access —
// consistent with the "no new git-clone/network dependency for the plugin
// manager itself" decision already made for dpp.vim/denops.vim in PR-1 (#476,
// D4). Individual plugins still require network via dpp-ext-installer; that
// is an existing, accepted dependency, not a new one introduced here.
// NOTE: BaseConfig は静的な "jsr:@shougo/dpp-vim" ではなく $NVIM_DPP_VIM
// (Nix store パス、nix/modules/neovim.nix 参照) から動的importする。
// これによりstate生成がネットワークに依存しなくなる — PR-1(#476, D4)で
// dpp.vim/denops.vim自体について既に取られた「プラグインマネージャ本体は
// 新たなgit clone/ネットワーク依存を持たない」方針と一貫している。
// 個々のプラグイン取得(dpp-ext-installer)は既存の許容されたネットワーク
// 依存であり、ここで新規に追加されるものではない。
const dppVimPath = Deno.env.get("NVIM_DPP_VIM");
if (!dppVimPath) {
  throw new Error(
    "config.ts: $NVIM_DPP_VIM is not set. Re-login (or restart the shell) " +
      "so home-manager session variables are re-sourced, then retry " +
      "dpp#make_state(). See init.lua's bootstrap guard for details.",
  );
}
const { BaseConfig } = await import(`file://${dppVimPath}/denops/dpp/base/config.ts`);

// Minimal structural types for readability only (Deno does not type-check
// this file at Neovim-startup time, so these are not imported from the
// ext packages — see the BaseConfig note above for why).
// 可読性のためのみの最小限の構造的型定義(Neovim起動時にこのファイルは
// 型チェックされないため、ext群からのimportはしていない。理由は上の
// BaseConfigの注記を参照)。
type Plugin = Record<string, unknown> & { name?: string; repo?: string };
type Toml = { plugins?: Plugin[] };
type LazyMakeStateResult = { plugins: Plugin[]; stateLines: string[] };
type ConfigArguments = {
  contextBuilder: {
    get(denops: unknown): Promise<[unknown, unknown]>;
    setGlobal(options: Record<string, unknown>): void;
  };
  denops: { call(fn: string, ...args: unknown[]): Promise<unknown> };
  dpp: {
    extAction(
      denops: unknown,
      context: unknown,
      options: unknown,
      extName: string,
      actionName: string,
      actionParams: Record<string, unknown>,
    ): Promise<unknown>;
  };
};
type ConfigReturn = {
  checkFiles?: string[];
  plugins: Plugin[];
  stateLines?: string[];
};

export class Config extends BaseConfig {
  override async config(args: ConfigArguments): Promise<ConfigReturn> {
    const { contextBuilder, denops, dpp } = args;

    // dpp-protocol-git を有効化(NVIM_DPP_PROTOCOL_GIT はinit.luaのbootstrapで
    // runtimepathへ追加済み。ここではプロトコル名を登録するのみ)。
    contextBuilder.setGlobal({ protocols: ["git"] });

    const [context, options] = await contextBuilder.get(denops);

    const nvimConfigDir = await denops.call("stdpath", "config") as string;

    // ------------------------------------------------------------------
    // TODO(human): セット×環境の対応構造をここに実装する
    //
    // 現状は下の「暫定フラットロードリスト」が14ファイルを固定の1本の
    // リストとして読み込んでいるだけで、「何をセットとして切るか」も
    // 「環境(Arch native / WSL2 / Docker等)で何を変えるか」も存在しない。
    //
    // 検討点:
    //   - セットの切り方: 現行の暗黙グループ(startup/status_line/mini/
    //     treesitter/lazy)をそのまま「セット」の単位にするか、機能軸
    //     (ai/finder/lsp等)で切り直すか
    //   - 環境判定: Deno.env / denops.call('has', ...) 等で Arch native
    //     と WSL2 をどう見分けるか(WSL2判定は $WSL_DISTRO_NAME 等が候補)
    //   - 合成方法: セット定義×環境プロファイルをどう掛け合わせて最終的な
    //     TOMLパスリスト(+ lazyフラグ)を組み立てるか
    //
    // (English mirror of the TODO above) Implement the "set x environment" composition here.
    //
    // Right now the "provisional flat load list" below just loads a single
    // fixed list of 14 files — there is no notion of "what counts as a
    // set" nor "what changes per environment" (Arch native / WSL2 / Docker).
    //
    // Points to consider:
    //   - How to cut sets: keep the current implicit groups (startup/
    //     status_line/mini/treesitter/lazy) as the unit, or re-cut along
    //     functional lines (ai/finder/lsp/...)?
    //   - Environment detection: how to distinguish Arch native vs WSL2
    //     (e.g. via Deno.env or denops.call('has', ...); $WSL_DISTRO_NAME
    //     is one candidate signal)?
    //   - Composition: how to combine set definitions x environment
    //     profiles into the final TOML path list (+ lazy flag)?
    // ------------------------------------------------------------------

    // 暫定フラットロードリスト: 現行init.luaと同じ14ファイル・同じ順序・
    // 同じlazy区分(startup/status_line/mini/treesitter は非遅延、
    // lazyグループのみ lazy=true)。上の設計課題が実装されるまでのつなぎ。
    // Provisional flat load list: same 14 files, same order, same lazy
    // grouping as the current init.lua (startup/status_line/mini/
    // treesitter are non-lazy; only the lazy group is lazy=true). A
    // stopgap until the design task above is implemented.
    const tomlFiles: { path: string; lazy: boolean }[] = [
      // startup
      { path: `${nvimConfigDir}/dpp.toml`, lazy: false },
      { path: `${nvimConfigDir}/dashboard.toml`, lazy: false },
      { path: `${nvimConfigDir}/style.toml`, lazy: false },
      { path: `${nvimConfigDir}/copilot.toml`, lazy: false },
      { path: `${nvimConfigDir}/codecompanion.toml`, lazy: false },
      { path: `${nvimConfigDir}/ddu_settings.toml`, lazy: false },

      // status line
      { path: `${nvimConfigDir}/status_line/lualine.toml`, lazy: false },
      { path: `${nvimConfigDir}/status_line/bufferline.toml`, lazy: false },
      { path: `${nvimConfigDir}/status_line/gitsigns.toml`, lazy: false },

      // mini
      { path: `${nvimConfigDir}/mini/mini.toml`, lazy: false },

      // treesitter (not lazy - nvim-treesitter 2025 rewrite dropped lazy support)
      { path: `${nvimConfigDir}/treesitter_settings.toml`, lazy: false },

      // lazy
      { path: `${nvimConfigDir}/dpp_lazy.toml`, lazy: true },
      { path: `${nvimConfigDir}/lsp_settings.toml`, lazy: true },
      { path: `${nvimConfigDir}/ddc_settings.toml`, lazy: true },
    ];

    let plugins: Plugin[] = [];
    for (const { path, lazy } of tomlFiles) {
      const toml = await dpp.extAction(
        denops,
        context,
        options,
        "toml",
        "load",
        { path, options: { lazy } },
      ) as Toml | undefined;
      plugins = [...plugins, ...(toml?.plugins ?? [])];
    }

    const lazyResult = await dpp.extAction(
      denops,
      context,
      options,
      "lazy",
      "makeState",
      { plugins },
    ) as LazyMakeStateResult | undefined;

    return {
      plugins: lazyResult?.plugins ?? plugins,
      stateLines: lazyResult?.stateLines ?? [],
      // TOML編集後の次回起動でdpp#check_files()がstate再生成を検知できるよう、
      // 読み込んだ全TOMLパスを登録する(init.luaのBufWritePost hook経由)。
      checkFiles: tomlFiles.map(({ path }) => path),
    };
  }
}
