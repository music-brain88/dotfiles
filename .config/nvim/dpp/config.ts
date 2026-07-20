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
const { BaseConfig } = await import(
  `file://${dppVimPath}/denops/dpp/base/config.ts`
);

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

    const nvimConfigDir = (await denops.call("stdpath", "config")) as string;

    // Docker 環境でENV DOTFILES_PROFILE=minimalを指定した場合、ここで読み込むTOMLを最小化することで
    // dpp#make_state()の結果を最小化することができる。dpp#check_files()は
    // TOMLの読み込み結果を見てstate.vimを生成するので、ここで読み込むTOMLを
    // 最小化すればstate.vimも最小化される。
    if (Deno.env.get("DOTFILES_PROFILE") === "minimal") {
      return {
        plugins: [],
        stateLines: [],
        checkFiles: [],
      };
    }
    // ------------------------------------------------------------------
    // 設計決定(2026-07-20, Learn by Doing): 環境は1つ、プロファイルは宣言で
    //
    // 「セット×環境」のマトリクスは採用しない。分ける理由が現状ないため、
    // ロードリストは下の1本(フラット)を正とする。環境差は検出(推測)せず、
    // 環境の側が DOTFILES_PROFILE で自己申告する(上の minimal 早期return)。
    // Docker は Dockerfile の ENV で minimal を宣言する。将来プロファイルが
    // 増えたら、この窓(環境変数1個)を広げる — 検出ロジックは足さない。
    //
    // Design decision (2026-07-20, Learn by Doing): one environment,
    // profiles are declared — not detected.
    // The "set x environment" matrix was intentionally NOT adopted: there is
    // currently no reason to split. The single flat list below is canonical.
    // Environments self-declare via DOTFILES_PROFILE (see the minimal
    // early-return above); Docker declares minimal in its Dockerfile ENV.
    // If more profiles appear, widen this one declaration window — do not
    // add detection heuristics.
    // ------------------------------------------------------------------

    // フラットロードリスト: 現行init.luaと同じ14ファイル・同じ順序・
    // 同じlazy区分(startup/status_line/mini/treesitter は非遅延、
    // lazyグループのみ lazy=true)。
    // Flat load list: same 14 files, same order, same lazy grouping as the
    // former init.lua (startup/status_line/mini/treesitter are non-lazy;
    // only the lazy group is lazy=true).
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
      const toml = (await dpp.extAction(
        denops,
        context,
        options,
        "toml",
        "load",
        { path, options: { lazy } },
      )) as Toml | undefined;
      plugins = [...plugins, ...(toml?.plugins ?? [])];
    }

    const lazyResult = (await dpp.extAction(
      denops,
      context,
      options,
      "lazy",
      "makeState",
      { plugins },
    )) as LazyMakeStateResult | undefined;

    return {
      plugins: lazyResult?.plugins ?? plugins,
      stateLines: lazyResult?.stateLines ?? [],
      // TOML編集後の次回起動でdpp#check_files()がstate再生成を検知できるよう、
      // 読み込んだ全TOMLパスを登録する(init.luaのBufWritePost hook経由)。
      checkFiles: tomlFiles.map(({ path }) => path),
    };
  }
}
