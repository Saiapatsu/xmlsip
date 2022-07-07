--[[
<Object type="0x01ff" id="Sheep">asdf<foo/></Object>
<!--
<
 Object 
        type="
		      0x01ff" 
			          id="
						  Sheep"
								>
								 asdf
								     <
									  foo
									     />
										   <
										    /Object>
Text
Tag
 STag
		Attr name
			  Attr value
					  Attr name
						  Attr value
								Attr name
								Tag end, opening
								 Text
								     Tag
									  STag
									     Attr name
										 Tag end, self-closing
										   Text
										   Tag
										    ETag
											        Text
													Tag
													EOF
-->

</Object>
<!--
</
  Object>
ETag
  Name
-->

<Object foo="bar"/>
<!--
<
 Object 
        foo="
		     bar"
			     />
Tag
 STag
		Attr name
			 Attr value
				 End of attributes, self-closing
-->
]]

local xmls = {}

-- Tag.
-- The character < or end of file.
-- Start tag: Transition to STag
-- End tag: Transition to ETag
-- Comment: Transition to Comment
-- Malformed: Transition to MalformedTag
-- etc.
function xmls.tag(str, pos) --> nil
	if pos > #str then
		return xmls.eof, pos
	end
	local sigil = str:sub(pos + 1, pos + 1)
	if sigil:match("%w") then
		return xmls.stag, pos + 1
	elseif sigil == "/" then
		if str:sub(pos + 2, pos + 2):match("%w") then
			return xmls.etag, pos + 2
		else
			return xmls.malformed, pos
		end
	elseif sigil == "!" then
		if str:sub(pos + 2, pos + 3) == "--" then
			return xmls.comment, pos + 4
		else
			return xmls.malformed, pos
		end
	elseif sigil == "?" then
		return xmls.pi, pos + 1
	else
		return xmls.malformed, pos
	end
	-- jump over <
	-- switch on whatever comes next
	-- malformed includes </> and </1> etc.
end

-- Name of starting tag.
-- Any name character
-- Transition to Attr
function xmls.stag(str, pos)
	local name
	name, pos = xmls.name(str, pos)
	pos = xmls.space(str, pos)
	return xmls.attr, pos, name
end

-- Name of ending tag.
-- Any name character
-- Transition to Text
function xmls.etag(str, pos)
	local name
	name, pos = xmls.name(str, pos)
	if str:sub(pos, pos) ~= ">" then
		error("Malformed closing tag at " .. pos) -- incorrect position
	end
	return xmls.text, pos + 1, name
end

-- Comment.
-- Anything
-- Transition to Text
function xmls.comment(str, pos) --> text content
	local pos2 = str:match("%-%->()", pos)
	if pos2 then
		return xmls.text, pos2, str:sub(pos, pos2 - 4)
	else
		-- unterminated
		return xmls.text, #str, str:sub(pos)
	end
end

-- Processing instruction.
-- Anything
-- Transition to Text
function xmls.pi(str, pos) --> text content
	local pos2 = str:match("?>()", pos)
	if pos2 then
		return xmls.text, pos2, str:sub(pos, pos2 - 3)
	else
		-- unterminated
		error("Unterminated processing instruction at " .. pos)
		-- return xmls.text, #str, str:sub(pos)
	end
end

-- Obviously malformed tag.
-- The character <
-- Transition to Text
function xmls.malformed(str, pos)
	-- zip to after >
	error("Malformed tag at " .. pos)
end

-- Attribute name or end of tag.
-- The characters /, > or any name character
-- Transition to Value or TagEnd
function xmls.attr(str, pos) --> text name or nil (stop iteratingg), unimplemented: end of name
	if str:match("^[^/>]", pos) then
		local name
		name, pos = xmls.name(str, pos)
		pos = xmls.space(str, pos)
		if str:sub(pos, pos) ~= "=" then
			error("Malformed attribute at " .. pos)
		end
		pos = xmls.space(str, pos + 1)
		return xmls.value, pos, name
	else
		return xmls.tagend, pos, nil
	end
end

-- Attribute value.
-- Anything
-- Transition to Attr
function xmls.value(str, pos) --> text value, (unimplemented) position of trailing "
	local value
	if str:sub(pos, pos) == '"' then
		value, pos = str:match("([^\"]*)()", pos + 1)
		if str:sub(pos, pos) ~= '"' then
			error("Unclosed attribute value at " .. pos)
		end
	else
		value, pos = str:match("([^']*)()", pos + 1)
		if str:sub(pos, pos) ~= "'" then
			error("Unclosed attribute value at " .. pos)
		end
	end
	pos = xmls.space(str, pos + 1)
	return xmls.attr, pos, value
end

-- End of tag
-- The characters / or >
-- Transition to Text
-- Returns whether it was self-closing?
function xmls.tagend(str, pos) --> true if opening tag, false if self-closing
	if str:sub(pos, pos) ~= "/" then
		return xmls.text, pos + 1, true
	else
		return xmls.text, pos + 2, false
	end
end

-- Plain text
-- Transition to Tag or EOF
function xmls.text(str, pos) --> text content
	str, pos = str:match("([^<]*)()", pos)
	return xmls.tag, pos, str
end

-- End of file
-- Error, shouldn't have read any further
function xmls.eof(str, pos)
	return error("Exceeding end of file")
end

function xmls.space(str, pos)
	return str:match("^[ \t\r\n]*()", pos)
end

function xmls.name(str, pos) --> name
	return str:match("^(%w+)()", pos)
end

---------------------------------------------

-- function xmls.tags()
-- end

-- xmls.attrs

-- xmls.waste -- only in Attr
-- xmls.wasteAttrs -- only in Attr
-- xmls.wasteContent -- only... where? Text?
-- better name?


-- testing

if false then

local back = {}
for k,v in pairs(xmls) do back[v] = k end

-- local str = "<foo bar='123'></foo>"
local file = assert(io.open("equip.xml"))
local str = file:read("*a")
file:close()

local op = xmls.text
local pos = 1
local ret

print()
while true do
	local a, b = back[op], pos
	local ret
	op, pos, ret = op(str, pos)
	print(a, b, ret)
	if op == xmls.eof then return end
end

end

return xmls
