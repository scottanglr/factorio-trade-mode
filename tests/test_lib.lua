local lib = {}

function lib.assert_true(value, message)
  if not value then
    error(message or "expected true")
  end
end

function lib.assert_false(value, message)
  if value then
    error(message or "expected false")
  end
end

function lib.assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. string.format(" (expected=%s actual=%s)", tostring(expected), tostring(actual)))
  end
end

function lib.assert_nil(value, message)
  if value ~= nil then
    error(message or "expected nil")
  end
end

function lib.run_cases(suite_name, cases)
  local results = {
    suite = suite_name,
    passed = 0,
    failed = 0,
    cases = {},
  }

  for _, case in ipairs(cases) do
    local ok, err = pcall(case.run)
    results.cases[#results.cases + 1] = {
      name = case.name,
      ok = ok,
      error = ok and nil or tostring(err),
    }
    if ok then
      results.passed = results.passed + 1
    else
      results.failed = results.failed + 1
    end
  end

  return results
end

return lib

