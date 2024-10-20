local M = {}

M.diagnostic_icons = {
    error = "", -- 0xEA87
    warn = "", -- 0xEA6C
    info = "", -- 0xEA74
    hint = "", -- 0xEA73
    success = "", -- 0xEAB2
}

M.lsp_icons = {
    diagnostic = "", -- 0xEAD8
    code_action = "󰌵", -- 0xF0335
    incoming = "󰏷 ", -- 0xF03F7
    outgoing = "󰏻 ", -- 0xF03FB
}

M.codicons = {
    Text = " ", -- 0xEA93
    Method = " ", -- 0xEA8C
    Function = " ", -- 0xEA8C
    Constructor = " ", -- 0xEA8C
    Field = " ", -- 0xEB5F
    Variable = " ", -- 0xEA88
    Class = " ", -- 0xEB5B
    Interface = " ", -- 0xEB61
    Module = " ", -- 0xEA8B
    Property = " ", -- 0xEB65
    Unit = " ", -- 0xEA96
    Value = " ", -- 0xEA95
    Enum = " ", -- 0xEA95
    Keyword = " ", -- 0xEB62
    Snippet = " ", -- 0xEA7B
    Color = " ", -- 0xEB5C
    File = " ", -- 0xEA7B
    Reference = " ", -- 0xEA94
    Folder = " ", -- 0xEA83
    EnumMember = " ", -- 0xEA95
    Constant = " ", -- 0xEB5D
    Struct = " ", -- 0xEA91
    Event = " ", -- 0xEA86
    Operator = " ", -- 0xEB64
    TypeParameter = " ", -- 0xEA92
    Null = "󰢤 ", -- 0xF08A4
    Copilot = " ", -- 0xF113
}

M.todo_icons = {
    todo = "", -- 0xEAB2
    fix = "", -- 0xEAD8
    warn = "", -- 0xEA6C
    test = "", -- 0xEBA8
    note = "", -- 0xEA7B
    pref = "", -- 0xEA86
    hack = "", -- 0xF452
    delete = "", -- 0xEA81
}

M.misc_icons = {
    file = "", -- 0xEA7B
    folder = "", -- 0xEA83
    cmd = "", -- 0xEA8C
    vim = "", -- 0xE82B
    lazy = "󰒲", -- 0xF04B2
}

return M
