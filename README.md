# xmlsip

**xmlsip** is an XML tokenizer in Lua and an army of functions to pull-parse its output.

Its goals are:
- to support the projects it was created for;
- to extract and modify data without losing whitespace/formatting;
- to challenge me to implement what I liked about (Hexml)[http://neilmitchell.blogspot.com/2016/12/new-xml-parser-hexml.html] and (pugixml)[http://www.aosabook.org/en/posa/parsing-xml-at-the-speed-of-light.html];
- to be like (jsonsip)[https://github.com/Saiapatsu/jsons], but for XML instead of JSON;
- to be fast and create no more tables or functions than necessary.

To start using xmlsip, wrap your string in a tokenizer state object and use its myriad methods to parse the XML document.
Consult the tests in the source code for common usage patterns.

```lua
local xmlsip = require "xmlsip"

local str = [[<examples>
	<example>&lt;Hello <bold>world</bold>!&gt;</example><!-- An example -->
</examples>]]

local xml = xmlsip.new(str)

-- declarative parsing - iterators are also available
xml:doTagsRoot {
	examples = {
		example = function(xml, name, pos) --> attr
			-- name: tag name
			-- pos: position of the <
			xml:skipAttr() --> tagend
			local text, posA, posB, opening = xml:getInnerText() --> outer
			print(name, pos, text)
		end,
		[xml.COMMENT] = function(xml, pos) --> comment
			local text = xml:stateValue() --> text
			print("COMMENT (" .. text .. ")")
		end,
	},
} --> eof

print(xml.names[xml.state]) -- "EOF"
```

The tokenizer state object is as follows:

* `str`: input XML document as string;
* `state`: current tokenizer state;
* `pos`: current tokenizer position;
* metatable: `xmlsip`, whose `__index` is itself.

Storing other data in this table is possible and useful.

The state object can be extended and patched simply by adding functions of the same name to the object, which is why all of the functions in xmlsip take a self argument and never refer to xmlsip itself.

## Notes

Closely following the standards is not one of xmlsip's goals.

xmlsip throws errors when given badly-formed data.

xmlsip does not normalize whitespace or EOLs and does not pay attention to nulls in the input.

xmlsip assumes all input to be encoded in UTF-8, but does not decode any characters. In particular, it accepts any Name that's vaguely UTF-8-shaped.

xmlsip does not pay attention to namespaces.

xmlsip does not process DTDs or stylesheets. Currently, internal DTDs are completely foreign to xmlsip and are treated as malformed XML.

xmlsip pays attention to entities. Parsing utilities tend to have entity/CDATA-respecting (as in innerText) and raw (as in innerXML) variants.

xmlsip tokenizes processing instructions just fine, but nothing in this library pays attention to them.

xmlsip does not verify whether an end tag matches the start tag.  
It is possible to modify xmlsip to do so with few architectural changes. There has been a failed attempt to do so.

xmlsip currently has no facilities to write XML nodes.  
It does, however, have a helper to replace arbitrary sections or contents of a node in an XML file.

The user is responsible for using xmlsip's methods at the correct state. There are a few asserts for the correct state strewn about, but it's still incredibly easy to mess up.

## States

A state is a function that takes an object with states in it, a string and a position and returns the position of the next state, the next state and one extra return value.

```lua
local str = [[<TagName key="value">]]
print(xmlsip:TEXT  (str,  1)) --  2, xmlsip.STAG,   1
print(xmlsip:STAG  (str,  2)) -- 10, xmlsip.ATTR,   9
print(xmlsip:ATTR  (str, 10)) -- 15, xmlsip.VALUE2, 13
print(xmlsip:VALUE2(str, 15)) -- 21, xmlsip.ATTR,   20
print(xmlsip:ATTR  (str, 21)) -- 21, xmlsip.TAGEND, nil
print(xmlsip:TAGEND(str, 21)) -- 22, xmlsip.TEXT,   true
print(xmlsip:TEXT  (str, 22)) -- 22, xmlsip.EOF,    22
print(xmlsip:EOF   (str, 22)) -- error: exceeded end of file
```

For most states, the return value is the end of the text content of the state.  
Therefore, the string return value of that state is between 2 and 9, including the start and excluding the end. That's `TagName`.

The exceptions are `ATTR` and `TAGEND`.  
`ATTR` returns a position if there was an attribute or `nil` if there was not.  
`TAGEND` returns `true` if the tag end was opening or `false` if it was self-closing.  

The tokenizer can be in one of the following states:
```
TEXT
STAG
ATTR
VALUE1
VALUE1ENT
VALUE2
VALUE2ENT
TAGEND
ETAG
ENTITY
CDATA
COMMENT
PI
EOF
```

It's also useful to think of `TEXT` after an opening `TAGEND` and `TEXT` after `ETAG` as special `INNER` and `OUTER` states respectively.  
These states do not actually exist in the code, but methods are often meant to be used just within a tag or just after a tag ends.

`TEXT` might be referred to as `PCDATA` (plain character data) elsewhere, but this library was created without knowing this.

The state output of the tokenizer conforms to this shape:
```
Document
	TEXT (Markup TEXT)* EOF

Markup
	Tag
	ETAG
	ENTITY
	CDATA
	COMMENT
	PI

Tag
	STAG ATTR (Value ATTR)* TAGEND

Value
	VALUE1 (VALUE1ENT VALUE1)*
	VALUE2 (VALUE2ENT VALUE1)*
```

This code will print every position, state and state return value in a given document.
```
local xml = xmlsip.new(str)
while xml.state ~= xml.EOF do print(xmlsip.names[xml.state], xml.pos, select(2, xml())) end
```

This is an example XML fragment broken down into states and their "return values".  
The third field is the position, the second field is the state and the first field is either the text between the position and the state's return value or the return value itself if it's not a number.
```
.<Object type="0x01ff" id="Sheep">asdf<foo/></Object>
"" TEXT 0
."Object" STAG 1
.       "type" ATTR 8
.             "0x01ff" VALUE2 14
.                     "id" ATTR 22
.                         "Sheep" VALUE2 26
.                               [nil] ATTR 32
.                               [true] TAGEND 32
.                                "asdf" TEXT 33
.                                     "foo" STAG 38
.                                        [nil] ATTR 41
.                                        [false] TAGEND 41
.                                          "" TEXT 43
.                                            "Object" ETAG 45
.                                                   "" TEXT 52
.                                                    EOF 53
```

xmlsip also has a few functions with the same signature as the states, which are meant to get to specific states faster and to keep string twiddling code out of the methods normally used with the tokenizer object.

- SKIPTAG:     ATTR   -> OUTER,  returns nil
- SKIPCONTENT: TAGEND -> OUTER,  returns end of content
- SKIPINNER:   INNER  -> OUTER,  returns end of content
- SKIPATTR:    ATTR   -> TAGEND, returns nil
- SKIPVALUE1:  VALUE1 -> ATTR,   returns end of value
- SKIPVALUE2:  VALUE2 -> ATTR,   returns end of value
