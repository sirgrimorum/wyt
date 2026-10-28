-- :WYTBrief, Today's brief as a PDF in a folder the Boox syncs, so the session
-- can start on paper. The folder comes from `project.outside_dir`.
local M = {}

--- The text of the PDF: the brief as Today's panel shows it, then the menu
--- as a list, since on paper there is nothing to pick from.
function M.text(brief, items, t)
    local lines = { require("wyt.today").compose(brief, t), "", t("brief_start") }
    for _, item in ipairs(items) do lines[#lines + 1] = "- " .. item.label end
    return table.concat(lines, "\n")
end

function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    local t = project.t
    project.outside_dir("brief_dir", t("brief_title"), t("brief_dir_q"), function(dir)
        -- The recap reads the last commit, and a save is what makes one. Only
        -- once there is a folder, so an Esc leaves no commit behind.
        require("wyt.ui").save_current()
        require("wyt.today").gather(project, function(brief, items)
            local title = (project.read_file(project.plan_path) or ""):match("^#%s+([^\r\n]+)") or ""
            local slug = project.slugify(title)
            -- One file per project, rewritten each time: the Boox shows the
            -- latest brief and the folder does not fill with old ones.
            local path = dir .. (slug ~= "" and ("today-" .. slug) or "today") .. ".pdf"
            local pdf = require("wyt.pdf").render(title, os.date("%Y-%m-%d %H:%M"), M.text(brief, items, t))
            if project.write_file(path, pdf) then
                vim.notify(t("brief_done"):format(path), vim.log.levels.INFO)
            end
        end)
    end)
end

return M
