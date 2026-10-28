-- :WYTAsk, a question to the model mid-session: what was her name, which year
-- was that, answered from the project's reference and the text on screen. It
-- only shows the answer; it never edits a file. A gap to fill in the text is a
-- wyt marker and :WYTResolve.
local M = {}

--- The text of the buffer on screen when it belongs to the project, unsaved
--- edits included: what the writer is looking at is what the question is about.
local function current_text(project_mod)
    local ui = require("wyt.ui")
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" or vim.bo.buftype ~= "" then return nil end
    if not vim.startswith(ui.canonical(name), ui.canonical(project_mod.project_root)) then return nil end
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    local ui = require("wyt.ui")
    local llm = require("wyt.llm")
    local t = project.t
    local ctx = {
        lang = project.lang,
        project = project.description_context(project.read_file(project.plan_path) or ""),
        reference = require("wyt.search").reference(project),
        text = current_text(project),
    }

    local ask
    ask = function()
        ui.ask_input({ title = t("ask_title"), question = t("ask_q") }, function(question)
            if question == nil then return end
            if vim.trim(question) == "" then return ask() end
            vim.notify(t("ask_thinking"), vim.log.levels.INFO)
            llm.ask(vim.tbl_extend("force", ctx, { question = question }), function(answer, err)
                if not answer then return vim.notify(t("llm_error") .. tostring(err), vim.log.levels.WARN) end
                ui.ask_select({ title = t("ask_title"), question = question .. "\n\n" .. answer, prompt = t("ask_menu") },
                    { t("ask_another"), t("ask_close") }, function(choice)
                        if choice == t("ask_another") then ask() end
                    end)
            end)
        end)
    end
    ask()
end

return M
