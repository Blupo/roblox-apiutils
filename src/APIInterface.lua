--!strict

type array<T> = {[number]: T}
type dictionary<T, TT> = {[T]: TT}

type DataTypeDescriptor = {
	Category: string,
	Name: string
}

type PropertyBehaviour = {
	Get: (Instance) -> any,
	Set: (Instance, any) -> (),
}

type ClassCheckBehaviour = (Instance) -> boolean
type ClassMemberBehaviour = PropertyBehaviour

---

local VALID_CLASS_MEMBER_TYPES: dictionary<string, boolean> = {
	Callback = true,
	Event = true,
	Function = true,
	Property = true,
}

local validContentProtocols = {
	rbxasset = true,
	rbxassetid = true,
	rbxgameasset = true,
	rbxhttp = true,
	rbxthumb = true,
	http = true,
	https = true
}

local checkDataType = function(valueType: DataTypeDescriptor, value: any): boolean
	local category: string = valueType.Category
	local name: string = valueType.Name
	
	if (category == "Class") then
		if (typeof(value) ~= "Instance") then return false end
		
		return value:IsA(name)
	elseif (category == "DataType") then
		if (name == "Content") then
			if (type(value) ~= "string") then return false end
			
			-- Content is case-sensitive, so no need to do string.lower
			local protocol = string.match(value, "(%d+)://.+")
			
			return (validContentProtocols[protocol] and true or false)
		else
			return (typeof(value) == name)
		end
	elseif (category == "Enum") then
		if (typeof(value) ~= "EnumItem") then return false end
		
		return (value.EnumType == Enum[name])
	elseif (category == "Primitive") then
		if ((name == "double") or (name == "float")) then
			return (type(value) == "number")
		elseif ((name == "int") or (name == "int64")) then
			if (type(value) ~= "number") then
				local floor = math.floor(value)
				
				return (value == floor)
			else
				return false
			end
		elseif (name == "bool") then
			return (type(value) == "boolean")
		else
			return (type(value) == name)
		end
	else
		warn("Value type category " .. category .. " is not supported")
		return false
	end
end

---

local APIInterface = {}

APIInterface.new = function(apiData)
	local self = {
		__APIData = apiData,
		__behaviourIndex = {
			ClassCheck = {},
			ClassMember = {}
		},
	}
	setmetatable(self, {__index = APIInterface})
	
	return self
end

-- Returns the property value of an object

APIInterface.GetProperty = function(self, object: Instance, propertyName: string, overrideClassName: string?, noCheck: boolean?, safe: boolean?): any
	local APIData = self.__APIData

	local objectClassName = overrideClassName or object.ClassName
	assert(APIData:DoesClassMemberExist(objectClassName, "Property", propertyName, noCheck), "Property " .. propertyName .. " does not exist, or class " .. objectClassName .. " does not exist")

	local actualPropertyClassName
	
	if (noCheck) then
		actualPropertyClassName = objectClassName
	else
		local properties = APIData:GetClassProperties(objectClassName)

		for className, classProperties in pairs(properties) do
			for i = 1, #classProperties do
				local classProperty = classProperties[i]
	
				if (classProperty.Name == propertyName) then
					actualPropertyClassName = className
					break
				end
			end
		end
	end

	if (APIData:IsClassMemberNative(actualPropertyClassName, "Property", propertyName)) then
		if (safe) then
			return pcall(function()
				return object[propertyName]
			end)
		else
			return object[propertyName]
		end
	else
		-- todo
		local classBehaviourIndex = self.__behaviourIndex.ClassMember[actualPropertyClassName]
		assert(classBehaviourIndex, "No behaviour table is defined for class " .. actualPropertyClassName)

		local propertyBehaviourTable = classBehaviourIndex.Property[propertyName]
		assert(propertyBehaviourTable, "No behaviour is defined for " .. actualPropertyClassName .. "." .. propertyName)

		if (safe) then
			return pcall(propertyBehaviourTable.Get, object)
		else
			return propertyBehaviourTable.Get(object)
		end
	end
end

APIInterface.SetProperty = function(self, object: Instance, propertyName: string, newValue: any, overrideClassName: string?, noCheck: boolean?, safe: boolean?)
	local APIData = self.__APIData

	local objectClassName = overrideClassName or object.ClassName 
	assert(APIData:DoesClassMemberExist(objectClassName, "Property", propertyName, noCheck), "Property " .. propertyName .. " does not exist, or class " .. objectClassName .. " does not exist")

	local actualPropertyClassName
	local propertyValueType

	if (noCheck) then
		actualPropertyClassName = objectClassName

		local property = APIData:GetClassMemberData(actualPropertyClassName, "Property", propertyName)
		propertyValueType = property.ValueType
	else
		local properties = APIData:GetClassProperties(objectClassName)

		for className, classProperties in pairs(properties) do
			for i = 1, #classProperties do
				local classProperty = classProperties[i]

				if (classProperty.Name == propertyName) then
					propertyValueType = classProperty.ValueType
					actualPropertyClassName = className
					break
				end
			end
		end
	end

	if (APIData:IsClassMemberNative(actualPropertyClassName, "Property", propertyName)) then
		assert(checkDataType(propertyValueType, newValue), "Type check failed for " .. propertyName .. ", expected " .. propertyValueType.Name)

		if (safe) then
			pcall(function()
				object[propertyName] = newValue
			end)
		else
			object[propertyName] = newValue
		end
	else
		local classMemberBehaviourIndex = self.__behaviourIndex.ClassMember[actualPropertyClassName]
		assert(classMemberBehaviourIndex, "No behaviour table is defined for class " .. actualPropertyClassName)

		local propertyBehaviourTable = classMemberBehaviourIndex.Property[propertyName]
		assert(propertyBehaviourTable, "No behaviour is defined for " .. actualPropertyClassName .. "." .. propertyName)
		
		assert(checkDataType(propertyValueType, newValue), "Type check failed for " .. propertyName .. ", expected " .. propertyValueType.Name)

		if (safe) then
			pcall(propertyBehaviourTable.Set, object, newValue)
		else
			propertyBehaviourTable.Set(object, newValue)
		end
	end
end

APIInterface.AddClassCheckBehavior = function(self, className: string, behaviour: ClassCheckBehaviour)
	local APIData = self.__APIData

	if (not APIData:DoesClassExist(className)) then return end
	if (APIData:IsClassNative(className)) then return end

	if (self.__behaviourIndex.ClassCheck[className]) then return end

	-- todo: verify that the behaviour behaves correctly (how?)

	self.__behaviourIndex.ClassCheck[className] = behaviour
end

APIInterface.AddClassMemberBehavior = function(self, className: string, memberType: string, memberName: string, behaviour: ClassMemberBehaviour)
	local APIData = self.__APIData

	if (memberType ~= "Property") then
		warn("Non-Property behaviours are not supported")
		return
	end

	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return end
	if (not APIData:DoesClassMemberExist(className, memberType, memberName)) then return end
	if (APIData:IsClassMemberNative(className, memberType, memberName)) then return end

	if (not self.__behaviourIndex.ClassMember[className]) then
		self.__behaviourIndex.ClassMember[className] = {
			Callback = {},
			Event = {},
			Function = {},
			Property = {},
		}
	end

	local classMemberBehaviourTable = self.__behaviourIndex.ClassMember[className][memberType]
	if (classMemberBehaviourTable[memberName]) then return end

	-- todo: verify that the behaviour behaves correctly

	classMemberBehaviourTable[memberName] = behaviour
end

return APIInterface