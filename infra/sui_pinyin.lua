-- sui_pinyin.lua — Simple UI
-- Shared pinyin sort-key helper for Chinese text sorting (author/title/
-- collection-name sorting menus across module_library.lua,
-- module_collections.lua, engines/sui_book_grid.lua, infra/sui_config.lua,
-- module_coverdeck.lua).
--
-- Converts a UTF-8 string into a sort key where Chinese characters are
-- replaced by (an approximation of) their FULL pinyin spelling, so
-- `key(a) < key(b)` orders the way a Chinese reader expects — instead of
-- the raw UTF-8 byte order that `:lower()` + `<` currently produces
-- everywhere in this codebase, which groups characters by Unicode code
-- point and has nothing to do with pronunciation.
--
-- NOTE: earlier revisions of this module only stored each character's
-- pinyin INITIAL letter, not its full syllable. That collapsed every
-- character sharing the same initial (e.g. "白"=bai, "杯"=bei, "不"=bu —
-- all "b") to an identical sort key, so they'd cluster together but sort
-- arbitrarily relative to each other. The starter table below (INITIAL)
-- still holds single letters for its ~200 hand-written entries, but
-- M.extend()/M.loadFromKoreaderIME() now store and expect the FULL
-- syllable — and since loadFromKoreaderIME's dictionary (thousands of
-- characters) overwrites any starter-table entry it also covers, this is
-- a non-issue in practice; only characters covered by NEITHER the IME
-- dictionary NOR the starter table's full set fall back to true single-
-- letter grouping.
--
-- ACCURACY NOTE — please read before treating this as "done":
-- This ships with a STARTER table (INITIAL below) covering only a few
-- hundred very common characters and surnames — enough to noticeably
-- improve sorting for typical book titles/author names, but nowhere near
-- exhaustive coverage of the ~20,000 CJK Unified Ideographs. Building and
-- verifying a full hanzi→pinyin-initial table from scratch is error-prone
-- (many characters, several polyphones), so rather than fabricate one, this
-- module is designed so a full table can be dropped in later:
--   • Any character not found in INITIAL falls through to the raw
--     character itself (M.sortKey below) — it does NOT break sorting, it
--     just doesn't improve it for that specific character. This means
--     growing INITIAL over time only ever helps, never regresses.
--   • M.extend(tbl) merges additional { [char] = "letter", ... } entries
--     at load time, so a full table can be sourced from an established
--     open-source pinyin dataset (e.g. pinyin4js, pinyin-pro, or any
--     "汉字拼音首字母对照表"), converted to this same shape, and merged in
--     without touching this file's logic.
-- Polyphone characters (multiple valid pronunciations, e.g. 重 chóng/zhòng)
-- are mapped to ONE common reading here — acceptable for sort-order
-- purposes, not for phonetic correctness.

local M = {}

-- ---------------------------------------------------------------------------
-- Starter table: character -> first pinyin letter (lowercase a-z).
-- Plain Lua table — extend directly, or via M.extend() below.
-- ---------------------------------------------------------------------------
local INITIAL = {
    -- Extremely common function/content words in Chinese book titles.
    ["的"]="d", ["一"]="y", ["是"]="s", ["不"]="b", ["了"]="l", ["人"]="r",
    ["我"]="w", ["在"]="z", ["有"]="y", ["他"]="t", ["这"]="z", ["中"]="z",
    ["大"]="d", ["来"]="l", ["上"]="s", ["国"]="g", ["个"]="g", ["到"]="d",
    ["说"]="s", ["为"]="w", ["子"]="z", ["和"]="h", ["你"]="n", ["地"]="d",
    ["出"]="c", ["道"]="d", ["也"]="y", ["时"]="s", ["年"]="n", ["得"]="d",
    ["就"]="j", ["那"]="n", ["要"]="y", ["下"]="x", ["以"]="y", ["生"]="s",
    ["会"]="h", ["自"]="z", ["着"]="z", ["去"]="q", ["之"]="z", ["过"]="g",
    ["家"]="j", ["学"]="x", ["对"]="d", ["可"]="k", ["她"]="t", ["里"]="l",
    ["后"]="h", ["小"]="x", ["心"]="x", ["多"]="d", ["天"]="t", ["而"]="e",
    ["能"]="n", ["好"]="h", ["都"]="d", ["然"]="r", ["没"]="m", ["日"]="r",
    ["于"]="y", ["起"]="q", ["还"]="h", ["发"]="f", ["成"]="c", ["事"]="s",
    ["只"]="z", ["作"]="z", ["当"]="d", ["想"]="x", ["看"]="k", ["文"]="w",
    ["无"]="w", ["开"]="k", ["手"]="s", ["十"]="s", ["用"]="y", ["主"]="z",
    ["行"]="x", ["方"]="f", ["前"]="q", ["所"]="s", ["本"]="b", ["见"]="j",
    ["经"]="j", ["头"]="t", ["面"]="m", ["公"]="g", ["同"]="t", ["三"]="s",
    ["已"]="y", ["老"]="l", ["从"]="c", ["种"]="z", ["机"]="j", ["新"]="x",
    ["世"]="s", ["界"]="j", ["爱"]="a", ["情"]="q", ["梦"]="m", ["书"]="s",
    ["记"]="j", ["传"]="c", ["史"]="s", ["山"]="s", ["水"]="s",
    ["风"]="f", ["云"]="y", ["月"]="y", ["星"]="x", ["光"]="g", ["夜"]="y",
    ["长"]="c", ["城"]="c", ["北"]="b", ["京"]="j", ["南"]="n", ["东"]="d",
    ["西"]="x", ["华"]="h", ["春"]="c", ["秋"]="q", ["夏"]="x", ["冬"]="d",

    -- Common surnames (for author-name sorting).
    ["王"]="w", ["李"]="l", ["张"]="z", ["刘"]="l", ["陈"]="c", ["杨"]="y",
    ["黄"]="h", ["赵"]="z", ["周"]="z", ["吴"]="w", ["徐"]="x", ["孙"]="s",
    ["马"]="m", ["朱"]="z", ["胡"]="h", ["郭"]="g", ["何"]="h", ["高"]="g",
    ["林"]="l", ["罗"]="l", ["郑"]="z", ["梁"]="l", ["谢"]="x", ["宋"]="s",
    ["唐"]="t", ["许"]="x", ["韩"]="h", ["冯"]="f", ["邓"]="d", ["曹"]="c",
    ["彭"]="p", ["曾"]="z", ["萧"]="x", ["田"]="t", ["董"]="d", ["袁"]="y",
    ["潘"]="p", ["蒋"]="j", ["蔡"]="c", ["余"]="y", ["杜"]="d", ["叶"]="y",
    ["程"]="c", ["苏"]="s", ["魏"]="w", ["吕"]="l", ["丁"]="d", ["任"]="r",
    ["沈"]="s", ["姚"]="y", ["卢"]="l", ["姜"]="j", ["崔"]="c", ["钟"]="z",
    ["谭"]="t", ["陆"]="l", ["汪"]="w", ["范"]="f", ["金"]="j", ["石"]="s",
    ["廖"]="l", ["贾"]="j", ["韦"]="w", ["白"]="b",
    ["邹"]="z", ["孟"]="m", ["熊"]="x", ["秦"]="q", ["邱"]="q", ["江"]="j",
    ["尹"]="y", ["薛"]="x", ["阎"]="y", ["段"]="d", ["雷"]="l", ["侯"]="h",
    ["龙"]="l", ["陶"]="t", ["黎"]="l",
}

-- Merge additional { [char] = "pinyin", ... } entries into INITIAL, e.g.
-- loaded from a fuller external dataset at plugin load time. Existing
-- entries are overwritten by `extra` on conflict — call this AFTER
-- requiring this module, before any sortKey() calls that need the new
-- coverage. Stores the FULL pinyin string (lowercased), not just its
-- first letter — see the "why full pinyin, not just the initial" note in
-- M.sortKey's doc comment below for why truncating to one letter breaks
-- ordering between characters that merely share the same initial
-- consonant (e.g. "白"=bai vs "杯"=bei vs "不"=bu all starting with "b").
function M.extend(extra)
    if type(extra) ~= "table" then return end
    for ch, py in pairs(extra) do
        if type(ch) == "string" and type(py) == "string" and py ~= "" then
            INITIAL[ch] = py:lower()
        end
    end
end

-- ---------------------------------------------------------------------------
-- UTF-8 iteration — splits a string into an array of "characters" (each
-- entry may be 1-4 bytes), since Lua string indexing is byte-based and
-- would otherwise slice multi-byte CJK sequences in half.
-- ---------------------------------------------------------------------------
local function utf8Chars(s)
    local chars = {}
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local len
        if     b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2
        else                  len = 1
        end
        -- Guard against a truncated/invalid tail (len would overrun #s).
        if i + len - 1 > n then len = n - i + 1 end
        chars[#chars + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

-- ---------------------------------------------------------------------------
-- M.sortKey(s) → string
--
-- Builds a comparison key for `s`: ASCII characters are lowercased as-is
-- (same behaviour as the `:lower()` calls this replaces); Chinese
-- characters found in INITIAL are replaced by their FULL pinyin syllable
-- (not just the first letter — see M.extend's doc comment for why that
-- distinction matters); anything else (unmapped CJK, punctuation, other
-- scripts/emoji) passes through unchanged, so it still sorts
-- deterministically, just not necessarily "correctly" by pronunciation.
-- Compare keys with plain `<`.
--
-- Using the full syllable (not just its initial) is what lets characters
-- sharing the same initial consonant — e.g. "白"=bai, "杯"=bei, "不"=bu —
-- sort correctly relative to EACH OTHER, not just cluster together with an
-- arbitrary internal order. True homophones (identical full pinyin, e.g.
-- two different characters both read "bei") still tie and fall back to
-- whatever order table.sort happens to produce — an acceptable, rare edge
-- case for a sort-order helper, not a diacritic/tone-accurate ordering.
-- ---------------------------------------------------------------------------
function M.sortKey(s)
    if type(s) ~= "string" or s == "" then return "" end
    local out = {}
    for _, ch in ipairs(utf8Chars(s)) do
        if #ch == 1 then
            out[#out + 1] = ch:lower()
        else
            out[#out + 1] = INITIAL[ch] or ch
        end
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- M.lt(a, b) → bool — convenience comparator, e.g. `table.sort(list, Pinyin.lt)`
-- when `list` is itself an array of strings to compare directly.
--
-- For the common case of sorting an array of ITEMS by a derived string
-- (e.g. filepaths sorted by title, or collection names sorted by display
-- name), prefer precomputing keys once into a lookup table and sorting
-- with that, rather than calling M.sortKey repeatedly inside the
-- comparator — see the call-site examples below. sortKey() re-walks the
-- whole string on every call, so precomputing avoids doing that
-- O(n log n) times over.
-- ---------------------------------------------------------------------------
function M.lt(a, b)
    return M.sortKey(a) < M.sortKey(b)
end

-- ---------------------------------------------------------------------------
-- M.loadFromKoreaderIME() — builds character -> pinyin entries from
-- KOReader's OWN bundled pinyin input-method dictionary
-- (ui/data/keyboardlayouts/zh_pinyin_data.lua), instead of vendoring a
-- second, separate pinyin dataset (e.g. a third-party lua-pinyin repo).
--
-- That file is shaped { [pinyin_syllable] = { candidate_word, ... }, ... }
-- (or { [pinyin_syllable] = "single_word" }) — used by KOReader's own zh_CN
-- IME candidate bar to go from typed pinyin to matching characters. This is
-- the REVERSE of what this module needs (word -> pinyin), so this function
-- inverts it: for every syllable key whose candidate is a SINGLE character,
-- that character is mapped to the syllable ITSELF (the full string, e.g.
-- "bai" — not just its first letter; see M.extend's doc comment for why
-- that distinction matters for sort correctness). Multi-character phrase
-- candidates are skipped — a phrase's OWN internal per-character reading
-- can't be inferred just from the syllable it's filed under, so mapping
-- every character in it to that one syllable would often be wrong for
-- every character after the first.
--
-- Single-character detection is done by BYTE length rather than full UTF-8
-- decoding: one CJK character is 3 UTF-8 bytes (4 only for rare
-- supplementary-plane characters, not a concern for book titles/author
-- names), while an N-character phrase is a multiple of that — so
-- `#w == 3` (with `#w == 4` also allowed) cheaply and reliably identifies
-- "exactly one character" without iterating the string.
--
-- Advantages over vendoring a third-party pinyin dataset:
--   • Already shipped with every KOReader install that has the zh_CN
--     keyboard layout — no extra data file to bundle, no separate license
--     to track alongside KOReader's own.
--   • Automatically stays in sync if KOReader's own dictionary is ever
--     corrected/expanded upstream — nothing in this plugin to update.
--
-- Idempotent (safe to call more than once — re-extends the same entries)
-- and safe when the dictionary module isn't present (e.g. a build without
-- the zh_CN keyboard layout, or a non-KOReader test environment): returns
-- 0 and leaves any existing INITIAL/extended entries untouched.
--
-- Returns the number of NEW character mappings learned this call.
-- ---------------------------------------------------------------------------
function M.loadFromKoreaderIME()
    local ok, code_map = pcall(require, "ui/data/keyboardlayouts/zh_pinyin_data")
    if not ok or type(code_map) ~= "table" then return 0 end

    -- learned[w]     = the best (lowercased) pinyin syllable found so far for
    --                  character w.
    -- learned_len[w] = the LENGTH of the `py` key that produced it — used to
    --                  prefer a more specific match over a shorter one.
    --
    -- A single character can legitimately appear under more than one key in
    -- this dictionary: IME "码表" data commonly includes both the character's
    -- full pinyin syllable (e.g. "bai") AND short abbreviation-style entries
    -- used for fast typing (e.g. "b" listing several common b-initial
    -- characters). Lua's pairs() iterates in unspecified order, so without
    -- this preference, which entry "wins" for a given character would be
    -- arbitrary — sometimes the informative "bai", sometimes the
    -- uninformative single-letter "b" (which is what caused the collapsed-
    -- to-one-letter sorting bug this function used to have: every b-initial
    -- character sorting as tied, since they all reduced to just "b").
    -- Preferring the LONGEST matching key consistently favours the fuller,
    -- more specific syllable.
    local learned     = {}
    local learned_len = {}
    local count = 0
    for py, candi in pairs(code_map) do
        if type(py) == "string" and py:match("^%a+$") then
            local words
            if type(candi) == "table" then
                words = candi
            elseif type(candi) == "string" then
                words = { candi }
            end
            if words then
                for _, w in ipairs(words) do
                    -- #w == 3 (or 4): exactly one CJK character by byte
                    -- length — see the doc comment above for why this
                    -- reliably excludes multi-character phrase entries
                    -- without a full UTF-8 decode.
                    if type(w) == "string" and (#w == 3 or #w == 4) then
                        local cur_len = learned_len[w]
                        if not cur_len or #py > cur_len then
                            if not cur_len then count = count + 1 end
                            learned[w]     = py:lower()
                            learned_len[w] = #py
                        end
                    end
                end
            end
        end
    end

    if count > 0 then M.extend(learned) end
    return count
end

-- Self-populate on load, best-effort: callers of M.sortKey/M.lt get the
-- benefit of KOReader's own (much larger) pinyin dictionary automatically,
-- with zero code changes at any of this module's call sites. Wrapped in
-- pcall by loadFromKoreaderIME itself, so a missing/unavailable dictionary
-- module (e.g. running this file outside KOReader) never breaks requiring
-- this module — it just falls back to the small STARTER table above.
local _learned_count = M.loadFromKoreaderIME()
local ok_logger, logger = pcall(require, "logger")
if ok_logger and logger then
    logger.info("simpleui: sui_pinyin: learned " .. tostring(_learned_count)
        .. " single-character readings from KOReader's pinyin IME dictionary")
end

return M