-- :WYTBrief, Today's brief as a PDF in a folder the Boox syncs, so the session
-- can start on paper. The folder comes from `project.outside_dir`.
local M = {}

--- The sections of the PDF: what Today's panel shows, each part under its
--- own heading so the page can be skimmed, then the menu as a list, since on
--- paper there is nothing to pick from.
function M.sections(brief, items, t)
    local out = {}
    if brief.paragraph then
        out[1] = { heading = t("brief_last"), text = t("brief_where"):format(brief.ago, brief.where) .. "\n\n" .. brief.paragraph }
    else
        out[1] = { heading = t("brief_last"), text = t("today_nothing_yet") }
    end
    if brief.summary then out[#out + 1] = { heading = t("brief_so_far"), text = brief.summary } end
    if brief.open then out[#out + 1] = { heading = t("brief_open"), text = brief.open } end
    if brief.prompt then out[#out + 1] = { heading = t("brief_prompt"), text = brief.prompt } end
    local start = {}
    for _, item in ipairs(items) do start[#start + 1] = "- " .. item.label end
    out[#out + 1] = { heading = t("brief_start"), text = table.concat(start, "\n") }
    return out
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
            local pdf = require("wyt.pdf").render(title, os.date("%Y-%m-%d %H:%M"), M.sections(brief, items, t))
            if project.write_file(path, pdf) then
                vim.notify(t("brief_done"):format(path), vim.log.levels.INFO)
            end
        end)
    end)
end

return M
