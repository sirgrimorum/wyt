-- :WYTBrief, Today's brief as a PDF on the Boox, so the session can start on
-- paper: sent to the project's ntfy topic, or else written to a folder the
-- tablet syncs, from `project.outside_dir`.
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

-- The brief, built: `callback(name, title, bytes)`.
local function build(project, callback)
    -- The recap reads the last commit, and a save is what makes one. Only once
    -- there is somewhere to send it, so an Esc leaves no commit behind.
    require("wyt.ui").save_current()
    require("wyt.today").gather(project, function(brief, items)
        local title = (project.read_file(project.plan_path) or ""):match("^#%s+([^\r\n]+)") or ""
        local slug = project.slugify(title)
        local name = (slug ~= "" and ("today-" .. slug) or "today") .. ".pdf"
        callback(name, title, require("wyt.pdf").render(title, os.date("%Y-%m-%d %H:%M"), M.sections(brief, items, project.t)))
    end)
end

function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    local t = project.t
    local ntfy = require("wyt.ntfy")
    local url, bad = ntfy.url(project)
    if bad then return vim.notify(bad, vim.log.levels.WARN) end
    if url then
        return build(project, function(name, title, bytes)
            local path = vim.fn.tempname() .. ".pdf"
            if not project.write_file(path, bytes) then return end
            ntfy.publish(url, path, name, title ~= "" and title or name, function(ok, err)
                os.remove(path)
                if ok then return vim.notify(t("brief_sent"):format(url), vim.log.levels.INFO) end
                vim.notify(t("ntfy_failed") .. tostring(err), vim.log.levels.WARN)
            end)
        end)
    end
    project.outside_dir("brief_dir", t("brief_title"), t("brief_dir_q"), function(dir)
        build(project, function(name, _, bytes)
            -- One file per project, rewritten each time: the Boox shows the
            -- latest brief and the folder does not fill with old ones.
            local path = dir .. name
            if project.write_file(path, bytes) then
                vim.notify(t("brief_done"):format(path), vim.log.levels.INFO)
            end
        end)
    end)
end

return M
