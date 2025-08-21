local uv = vim.loop
local loc = require("wyt.localization")
local llm = require("wyt.llm")
local project = require("wyt.project")
local group = require("wyt.group")

local M = {}

local function ensure_section_exists(content, section)
    local section_header = "## " .. project.t(section)
    if not content:find(section_header) then
        return content .. "\n" .. section_header .. "\n"
    end
    return content
end

local multi_select = require("wyt.group").multi_select

function M.new_idea()
    local plan_content = project.read_file(project.plan_path) or ""
    plan_content = ensure_section_exists(plan_content, "ideas_section")
    local groups = group.get_groups(plan_content)
    vim.ui.input({prompt = loc.t("idea_name")}, function(idea_name)
        if not idea_name or idea_name == "" then return end
        vim.ui.select({loc.t("yes"), loc.t("no")}, {prompt = loc.t("use_llm")}, function(use_llm)
            local final_idea = idea_name
            if use_llm == loc.t("yes") then
                -- ToDo: final_idea = llm.improve_idea(idea_name)
            end
            local function add_idea(selected_groups)
                plan_content = project.add_item_to_section(plan_content, "ideas_section", final_idea)
                if selected_groups and #selected_groups > 0 then
                    for _, group_selected in ipairs(selected_groups) do
                        plan_content = project.add_item_to_section(plan_content, project.t("group_tag") .. ": " .. group_selected, final_idea)
                        plan_content = group.mark_ideas_as_grouped(plan_content, {final_idea}, group_selected)
                    end
                end
                project.write_file(project.plan_path, plan_content)
                project.commit_changes("Add idea: " .. idea_name)
                print(loc.t("idea_added") .. final_idea)
                vim.cmd("edit " .. project.plan_path)
                -- Posiciona el cursor en la idea recién agregada
                local idea_line = nil
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line:find(final_idea, 1, true) then
                        idea_line = i
                        break
                    end
                end
                if idea_line then
                    vim.api.nvim_win_set_cursor(0, {idea_line, 0})
                end
                vim.cmd("normal! zz")
            end
            if #groups > 0 then
                multi_select(groups, {prompt = loc.t("add_to_group")}, function(selected)
                    add_idea(selected)
                end)
            else
                add_idea({})
            end
        end)
    end)
end

return M