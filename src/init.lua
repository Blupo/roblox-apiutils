local APIData = require(script.APIData)
local APIInterface = require(script.APIInterface)

---

local APIUtils = {}

APIUtils.createAPIData = APIData.new
APIUtils.createAPIInterface = APIInterface.new

return APIUtils