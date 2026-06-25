local M = {}

local function list(lhses)
  if lhses == nil or lhses == false then
    return {}
  end

  if type(lhses) == "table" then
    return lhses
  end

  return { lhses }
end

function M.set(mode, lhses, rhs, opts)
  for _, lhs in ipairs(list(lhses)) do
    if lhs and lhs ~= "" then
      vim.keymap.set(mode, lhs, rhs, opts)
    end
  end
end

function M.del(mode, lhses, opts)
  for _, lhs in ipairs(list(lhses)) do
    if lhs and lhs ~= "" then
      pcall(vim.keymap.del, mode, lhs, opts)
    end
  end
end

function M.flatten(tbl)
  local out = {}
  for _, value in pairs(tbl or {}) do
    for _, lhs in ipairs(list(value)) do
      if lhs and lhs ~= "" then
        out[#out + 1] = lhs
      end
    end
  end
  return out
end

return M
