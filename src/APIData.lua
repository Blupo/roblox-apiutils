--!strict

type array<T> = {[number]: T}
type dictionary<T, TT> = {[T]: TT}
type anyTable = dictionary<any, any>

-- Class (member) types

type DataTypeDescriptor = {
	Category: string,
	Name: string
}

type ParameterDescriptor = {
	Name: string,
	Type: DataTypeDescriptor
}

type APIFunctionParameterDescriptor = {
	Name: string,
	Type: DataTypeDescriptor,
	Default: string?
}

type APICallback = {
	MemberType: string,
	Name: string,

	Parameters: array<ParameterDescriptor>,
	ReturnType: DataTypeDescriptor,

	Security: string,
	ThreadSafety: string,
	Tags: array<string>?,
}

type APIEvent = {
	MemberType: string,
	Name: string,

	Parameters: array<ParameterDescriptor>,

	Security: string,
	ThreadSafety: string,
	Tags: array<string>?,
}

type APIFunction = {
	MemberType: string,
	Name: string,

	Parameters: array<APIFunctionParameterDescriptor>,
	ReturnType: DataTypeDescriptor,

	Security: string,
	ThreadSafety: string,
	Tags: array<string>?,
}

type APIProperty = {
	Category: string,
	MemberType: string,
	Name: string,

	Security: {
		Read: string,
		Write: string
	},

	Serialization: {
		CanLoad: boolean,
		CanSave: boolean
	},

	Tags: array<string>?,

	ValueType: DataTypeDescriptor,
	ThreadSafety: string,
}

type APIClassMember = APICallback | APIEvent | APIFunction | APIProperty

type APIClass = {
	Members: array<APIClassMember>,

	MemoryCategory: string,
	Name: string,
	Superclass: string,

	Tags: array<string>?
}

-- Types for Enums and EnumItems

type APIEnumItem = {
	Name: string,
	Value: number -- integer
}

type APIEnum = {
	Items: array<APIEnumItem>,
	Name: string
}

-- JSON API dump

type JSONAPIDump = {
	Classes: array<APIClass>,
	Enums: array<APIEnum>,
	Version: number,
}

-- Used by APIData.__getClassMembers for filtering the member list

type GetClassMembersParams = {
	IncludeInheritedMembers: boolean?,
	RemoveOverridenMembers: boolean?,
	FilterCallback: ((string, APIClassMember) -> boolean)?
}

---

local VALID_API_DUMP_VERSIONS: dictionary<number, boolean> = {
	[1] = true,
}

local VALID_CLASS_MEMBER_TYPES: dictionary<string, boolean> = {
	Callback = true,
	Event = true,
	Function = true,
	Property = true,
}

-- copies a table's values, including for k/v that are also ables
-- does not copy metatables
local tableDeepCopy

tableDeepCopy = function(tab: anyTable): anyTable
	local copy = {}

	if (type(tab) == "table") then
		for k, v in pairs(tab) do
			copy[tableDeepCopy(k)] = tableDeepCopy(v)
		end
	else
		return tab
	end

	return copy
end

---

local APIData = {}

export type APIData = {
	__data: {
		Classes: array<APIClass>,
		Enums: array<APIEnum>
	},

	__nativityIndex: {
		Classes: array<boolean>,
		ClassMembers: dictionary<number, array<boolean>>,
		Enums: array<boolean>,
		EnumItems: dictionary<number, array<boolean>>,
	},

	__indexMappings: {
		Classes: dictionary<string, number>,
		ClassMembers: array<{
			Callback: dictionary<string, number>,
			Event: dictionary<string, number>,
			Function: dictionary<string, number>,
			Property: dictionary<string, number>
		}>,
		Enums: dictionary<string, number>,
		EnumItems: array<{
			Name: dictionary<string, number>,
			Value: dictionary<number, number>,
		}>
	},
}

APIData.new = function(apiDump: JSONAPIDump)
	-- todo: check that EnumItems have integer Values

	-- API dump should be immutable
	apiDump = tableDeepCopy(apiDump)

	-- verify version
	assert(VALID_API_DUMP_VERSIONS[apiDump.Version], "API dump version " .. apiDump.Version .. " is not supported")

	local self: APIData = {
		__data = {
			Classes = apiDump.Classes,
			Enums = apiDump.Enums,
		},

		__nativityIndex = {
			Classes = {},
			ClassMembers = {},
			Enums = {},
			EnumItems = {},
		},

		__indexMappings = {
			Classes = {},
			ClassMembers = {},
			Enums = {},
			EnumItems = {},
		},
	}
	setmetatable(self, {__index = APIData})

	-- create mappings, populate nativity for classes
	for i = 1, #self.__data.Classes do
		local classData = self.__data.Classes[i]

		self.__nativityIndex.Classes[i] = true
		self.__nativityIndex.ClassMembers[i] = {}

		self.__indexMappings.Classes[classData.Name] = i
		self.__indexMappings.ClassMembers[i] = {
			Callback = {},
			Event = {},
			Function = {},
			Property = {}
		}

		for j = 1, #classData.Members do
			local classMember = classData.Members[j]

			self.__nativityIndex.ClassMembers[i][j] = true
			self.__indexMappings.ClassMembers[i][classMember.MemberType][classMember.Name] = j
		end
	end

	-- now for enums
	for i = 1, #self.__data.Enums do
		local enumData = self.__data.Enums[i]

		self.__nativityIndex.Enums[i] = true
		self.__nativityIndex.EnumItems[i] = {}

		self.__indexMappings.Enums[enumData.Name] = i
		self.__indexMappings.EnumItems[i] = {
			Name = {},
			Value = {},
		}

		for j = 1, #enumData.Items do
			local enumItem = enumData.Items[j]

			self.__nativityIndex.EnumItems[i][j] = true
			self.__indexMappings.EnumItems[i].Name[enumItem.Name] = j
			self.__indexMappings.EnumItems[i].Value[enumItem.Value] = j
		end
	end

	return self
end

-- Returns an APIClass
APIData.GetClassData = function(self: APIData, className: string): APIClass?
	local classIndex: number? = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	return self.__data.Classes[classIndex]
end

-- Returns an array of class names, in the form
-- { className, superclass1, ..., "Instance" }
APIData.GetClassHierarchy = function(self: APIData, className: string): array<string>?
	local hierarchy: array<string> = {}

	local classIndex: number? = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	while (classIndex) do
		local classData: APIClass = self.__data.Classes[classIndex]
		local superclass: string = classData.Superclass

		hierarchy[#hierarchy + 1] = classData.Name

		if (superclass ~= "<<<ROOT>>>") then
			classIndex = self.__indexMappings.Classes[superclass]
		else
			break
		end
	end

	return hierarchy
end

-- Returns a dictionary containing arrays of class members
APIData.__getClassMembers = function(self: APIData, className: string, memberType: string, filterParams: GetClassMembersParams?): dictionary<string, array<APIClassMember>>?
	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return end

	filterParams = filterParams or {}
	local includeInheritedMembers = (filterParams.IncludeInheritedMembers == nil) and true or filterParams.IncludeInheritedMembers
	local removeOverridenMembers = (filterParams.RemoveOverridenMembers == nil) and true or filterParams.RemoveOverridenMembers

	local members: dictionary<string, array<APIClassMember>> = {}
	local overrides: dictionary<string, boolean> = {}

	local classIndex: number = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	while (classIndex) do
		local classData: APIClass = self.__data.Classes[classIndex]

		members[classData.Name] = {}
		local classMembers: array<APIClassMember> = members[classData.Name]

		for i = 1, #classData.Members do
			local member: APIClassMember = classData.Members[i]

			if ((member.MemberType == memberType) and ((filterParams.FilterCallback == nil) and true or filterParams.FilterCallback(classData.Name, member))) then
				if (removeOverridenMembers) then
					if (not overrides[member.Name]) then
						classMembers[#classMembers + 1] = member
						overrides[member.Name] = true
					end
				else
					classMembers[#classMembers + 1] = member
				end
			end
		end

		if (includeInheritedMembers and (classData.Superclass ~= "<<<ROOT>>>")) then
			classIndex = self.__indexMappings.Classes[classData.Superclass]
		else
			break
		end
	end

	return members
end

APIData.GetClassMemberData = function(self: APIData, className: string, memberType: string, memberName: string): APIClassMember?
	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return end

	local classIndex: number = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	local classMemberIndex = self.__indexMappings.ClassMembers[classIndex][memberType][memberName]
	if (not classMemberIndex) then return end

	return self.__data.Classes[classIndex].Members[classMemberIndex]
end

-- Aliases for __getClassMembers for specific member types
APIData.GetClassCallbacks = function(self: APIData, className: string, filterParams: GetClassMembersParams?): dictionary<string, array<APIClassMember>>?
	return APIData.__getClassMembers(self, className, "Callback", filterParams)
end

APIData.GetClassEvents = function(self: APIData, className: string, filterParams: GetClassMembersParams?): dictionary<string, array<APIClassMember>>?
	return APIData.__getClassMembers(self, className, "Event", filterParams)
end

APIData.GetClassFunctions = function(self: APIData, className: string, filterParams: GetClassMembersParams?): dictionary<string, array<APIClassMember>>?
	return APIData.__getClassMembers(self, className, "Function", filterParams)
end

APIData.GetClassProperties = function(self: APIData, className: string, filterParams: GetClassMembersParams?): dictionary<string, array<APIClassMember>>?
	return APIData.__getClassMembers(self, className, "Property", filterParams)
end

-- Returns if a class exists
APIData.DoesClassExist = function(self: APIData, className: string): boolean
	local classIndex: number? = self.__indexMappings.Classes[className]
	return (type(classIndex) == "number")
end

-- Returns if a class member exists
APIData.DoesClassMemberExist = function(self: APIData, className: string, memberType: string, memberName: string, includeInheritedMembers: boolean?): boolean
	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return false end

	includeInheritedMembers = (includeInheritedMembers == nil) and true or includeInheritedMembers

	local classIndex: number? = self.__indexMappings.Classes[className]
	if (not classIndex) then return false end

	while (classIndex) do
		local classData = self.__data.Classes[classIndex]
		local superclass = classData.Superclass

		local classMemberIndex: number? = self.__indexMappings.ClassMembers[classIndex][memberType][memberName]
		
		if (classMemberIndex) then
			return true
		end

		if (includeInheritedMembers and (superclass ~= "<<<ROOT>>>")) then
			classIndex = self.__indexMappings.Classes[superclass]
		else
			break
		end
	end

	return false
end

-- Returns if a class is part of the original API dump
APIData.IsClassNative = function(self: APIData, className: string): boolean?
	local classIndex: number? = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	return self.__nativityIndex.Classes[classIndex]
end

-- Returns if a class member is part of the original API dump
APIData.IsClassMemberNative = function(self: APIData, className: string, memberType: string, memberName: string): boolean?
	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return end

	local classIndex: number? = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	local classMemberIndex: number? = self.__indexMappings.ClassMembers[classIndex][memberType][memberName]
	if (not classMemberIndex) then return end

	return self.__nativityIndex.ClassMembers[classIndex][classMemberIndex]
end

-- Returns an APIEnum
APIData.GetEnumData = function(self: APIData, enumName: string): APIEnum?
	local enumIndex: number? = self.__indexMappings.Enums[enumName]
	if (not enumIndex) then return end

	return self.__data.Enums[enumIndex]
end

-- Returns if an Enum is part of the original API dump
APIData.IsEnumNative = function(self: APIData, enumName: string): boolean?
	local enumIndex: number? = self.__indexMappings.Enums[enumName]
	if (not enumIndex) then return end

	return self.__nativityIndex.Enums[enumIndex]
end

-- Returns if an EnumItem is part of the original API dump
APIData.IsEnumItemNative = function(self: APIData, enumName: string, enumItemNameOrValue: string | number): boolean?
	local enumIndex: number? = self.__indexMappings.Enums[enumName]
	if (not enumIndex) then return end

	local enumItemIndex: number?

	if (type(enumItemNameOrValue) == "string") then
		enumItemIndex = self.__indexMappings.EnumItems[enumIndex].Name[enumItemNameOrValue]
	elseif (type(enumItemNameOrValue) == "number") then
		enumItemIndex = self.__indexMappings.EnumItems[enumIndex].Value[enumItemNameOrValue]
	end

	if (not enumItemIndex) then return end
	return self.__nativityIndex.EnumItems[enumIndex][enumItemIndex]
end

-- Adds a new APIClass
APIData.AddClass = function(self: APIData, apiClass: APIClass)
	local className = apiClass.Name
	local classIndex = self.__indexMappings.Classes[className]
	if (classIndex) then return end

	local newClassIndex = #self.__data.Classes + 1

	self.__data.Classes[newClassIndex] = tableDeepCopy(apiClass)
	self.__indexMappings.Classes[className] = newClassIndex
	self.__nativityIndex.Classes[newClassIndex] = false
end

-- Adds a new APIClassMember
APIData.AddClassMember = function(self: APIData, className: string, apiClassMember: APIClassMember)
	local memberName = apiClassMember.Name
	local memberType = apiClassMember.MemberType
	if (not VALID_CLASS_MEMBER_TYPES[memberType]) then return end

	local classIndex = self.__indexMappings.Classes[className]
	if (not classIndex) then return end

	local classMemberIndex = self.__indexMappings.ClassMembers[classIndex][memberType][memberName]
	if (classMemberIndex) then return end

	local newClassMemberIndex = #self.__data.Classes[classIndex].Members + 1

	self.__data.Classes[classIndex].Members[newClassMemberIndex] = tableDeepCopy(apiClassMember)
	self.__indexMappings.ClassMembers[classIndex][memberType][memberName] = newClassMemberIndex
	self.__nativityIndex.ClassMembers[classIndex][newClassMemberIndex] = false
end

---

return APIData