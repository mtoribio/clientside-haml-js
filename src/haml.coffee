root = this

root.haml =

  ###
    Compiles the haml in the script block with ID templateId
    Returns a javascript function
  ###
  compileHaml: (templateId) ->
    @_compileHamlTemplate templateId, new haml.JsCodeGenerator()

  ###
    Compiles the haml in the script block with ID templateId using the coffeescript generator
    Returns a javascript function
  ###
  compileCoffeeHaml: (templateId) ->
    @_compileHamlTemplate templateId, new haml.CoffeeCodeGenerator()

  ###
    Compiles the haml in the passed in string
    Returns a javascript function
  ###
  compileStringToJs: (string) ->
    codeGenerator = new haml.JsCodeGenerator()
    result = @_compileHamlToJs new haml.Tokeniser(template: string), codeGenerator
    codeGenerator.generateJsFunction(result)

  ###
    Compiles the haml in the passed in string using the coffeescript generator
    Returns a javascript function
  ###
  compileCoffeeHamlFromString: (string) ->
    codeGenerator = new haml.CoffeeCodeGenerator()
    result = @_compileHamlToJs new haml.Tokeniser(template: string), codeGenerator
    codeGenerator.generateJsFunction(result)

  ###
    Compiles the haml in the passed in string
    Returns the javascript function source

    This is mainly used for precompiling the haml templates so they can be packaged.
  ###
  compileHamlToJsString: (string) ->
    result = 'function (context) {\n'
    result += @_compileHamlToJs new haml.Tokeniser(template: string), new haml.JsCodeGenerator()
    result += '}\n'

  _compileHamlTemplate: (templateId, codeGenerator) ->
    haml.cache ||= {}

    return haml.cache[templateId] if haml.cache[templateId]

    result = @_compileHamlToJs new haml.Tokeniser(templateId: templateId), codeGenerator
    fn = codeGenerator.generateJsFunction(result)
    haml.cache[templateId] = fn
    fn

  _compileHamlToJs: (tokeniser, generator) ->
    elementStack = []

    generator.initOutput()

    # HAML -> WS* (
    #          TEMPLATELINE
    #          | DOCTYPE
    #          | IGNOREDLINE
    #          | EMBEDDEDJS
    #          | JSCODE
    #          | COMMENTLINE
    #         )* EOF
    tokeniser.getNextToken()
    while !tokeniser.token.eof
      if !tokeniser.token.eol
        indent = haml._whitespace(tokeniser)
        generator.setIndent(indent)
        if tokeniser.token.eol
          generator.outputBuffer.append(HamlRuntime.indentText(indent) + '\n')
        else if tokeniser.token.doctype
          haml._doctype(tokeniser, indent, generator)
        else if tokeniser.token.exclamation
          haml._ignoredLine(tokeniser, indent, elementStack, generator)
        else if tokeniser.token.equal or tokeniser.token.escapeHtml or tokeniser.token.unescapeHtml or
        tokeniser.token.tilde
          haml._embeddedJs(tokeniser, indent, elementStack, innerWhitespace: true, generator)
        else if tokeniser.token.minus
          haml._jsLine(tokeniser, indent, elementStack, generator)
        else if tokeniser.token.comment or tokeniser.token.slash
          haml._commentLine(tokeniser, indent, elementStack, generator)
        else if tokeniser.token.amp
          haml._escapedLine(tokeniser, indent, elementStack, generator)
        else if tokeniser.token.filter
          haml._filter(tokeniser, indent, generator)
        else
          haml._templateLine(tokeniser, elementStack, indent, generator)
      else
        tokeniser.getNextToken()

    haml._closeElements(0, elementStack, tokeniser, generator)
    generator.closeAndReturnOutput()

  _doctype: (tokeniser, indent, generator) ->
    if tokeniser.token.doctype
      generator.outputBuffer.append(HamlRuntime.indentText(indent))
      tokeniser.getNextToken()
      contents = tokeniser.skipToEOLorEOF()
      if contents and contents.length > 0
        params = contents.split(/\s+/)
        switch params[0]
          when 'XML'
            if params.length > 1
              generator.outputBuffer.append("<?xml version='1.0' encoding='#{params[1]}' ?>")
            else
              generator.outputBuffer.append("<?xml version='1.0' encoding='utf-8' ?>")
          when 'Strict' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">')
          when 'Frameset' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">')
          when '5' then generator.outputBuffer.append('<!DOCTYPE html>')
          when '1.1' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">')
          when 'Basic' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">')
          when 'Mobile' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">')
          when 'RDFa' then generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML+RDFa 1.0//EN" "http://www.w3.org/MarkUp/DTD/xhtml-rdfa-1.dtd">')
      else
        generator.outputBuffer.append('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">')
      generator.outputBuffer.append("\n")

  _filter: (tokeniser, indent, generator) ->
    if tokeniser.token.filter
      filter = tokeniser.token.tokenString
      throw tokeniser.parseError("Filter '#{filter}' not registered. Filter functions need to be added to 'haml.filters'.") unless haml.filters[filter]
      tokeniser.skipToEOLorEOF()
      tokeniser.getNextToken()
      i = haml._whitespace(tokeniser)
      filterBlock = []
      while (!tokeniser.token.eof and i > indent)
        tokeniser.pushBackToken()
        line = tokeniser.skipToEOLorEOF()
        filterBlock.push(haml.HamlRuntime.indentText(i - indent - 1) + line)
        tokeniser.getNextToken()
        i = haml._whitespace(tokeniser)
      haml.filters[filter](filterBlock, generator, haml.HamlRuntime.indentText(indent), tokeniser.currentParsePoint())
      tokeniser.pushBackToken()

  _commentLine: (tokeniser, indent, elementStack, generator) -> 
    if tokeniser.token.comment
      tokeniser.skipToEOLorEOF()
      tokeniser.getNextToken()
      i = haml._whitespace(tokeniser)
      while (!tokeniser.token.eof and i > indent)
        tokeniser.skipToEOLorEOF()
        tokeniser.getNextToken()
        i = haml._whitespace(tokeniser)
      tokeniser.pushBackToken()
    else if tokeniser.token.slash
      haml._closeElements(indent, elementStack, tokeniser, generator)
      generator.outputBuffer.append(HamlRuntime.indentText(indent))
      generator.outputBuffer.append("<!--")
      contents = tokeniser.skipToEOLorEOF()

      generator.outputBuffer.append(contents) if contents and contents.length > 0

      if contents and _(contents).startsWith('[') and contents.match(/\]\s*$/)
        elementStack[indent] = htmlConditionalComment: true
        generator.outputBuffer.append(">")
      else
        elementStack[indent] = htmlComment: true

      if haml._tagHasContents(indent, tokeniser)
        generator.outputBuffer.append("\n")

  _escapedLine: (tokeniser, indent, elementStack, generator) ->
    if tokeniser.token.amp
      haml._closeElements(indent, elementStack, tokeniser, generator)
      generator.outputBuffer.append(HamlRuntime.indentText(indent))
      contents = tokeniser.skipToEOLorEOF()
      generator.outputBuffer.append(haml.HamlRuntime.escapeHTML(contents)) if (contents && contents.length > 0)
      generator.outputBuffer.append("\n")

  _ignoredLine: (tokeniser, indent, elementStack, generator) ->
    if tokeniser.token.exclamation
      tokeniser.getNextToken()
      indent += haml._whitespace(tokeniser) if tokeniser.token.ws
      tokeniser.pushBackToken()
      haml._closeElements(indent, elementStack, tokeniser, generator)
      contents = tokeniser.skipToEOLorEOF()
      generator.outputBuffer.append(HamlRuntime.indentText(indent) + contents + '\n')

  _embeddedJs: (tokeniser, indent, elementStack, tagOptions, generator) ->
    haml._closeElements(indent, elementStack, tokeniser, generator) if elementStack
    if tokeniser.token.equal or tokeniser.token.escapeHtml or tokeniser.token.unescapeHtml or tokeniser.token.tilde
      escapeHtml = tokeniser.token.escapeHtml or tokeniser.token.equal
      perserveWhitespace = tokeniser.token.tilde
      currentParsePoint = tokeniser.currentParsePoint()
      expression = tokeniser.skipToEOLorEOF()
      indentText = HamlRuntime.indentText(indent)
      generator.outputBuffer.append(indentText) if !tagOptions or tagOptions.innerWhitespace
      generator.appendEmbeddedCode(indentText, expression, escapeHtml, perserveWhitespace, currentParsePoint)
      generator.outputBuffer.append("\n") if !tagOptions or tagOptions.innerWhitespace

  _jsLine: (tokeniser, indent, elementStack, generator) ->
    if tokeniser.token.minus
      haml._closeElements(indent, elementStack, tokeniser, generator)

      line = tokeniser.skipToEOLorEOF()
      generator.setIndent(indent)
      generator.appendCodeLine(line)

      if generator.lineMatchesStartFunctionBlock(line)
        elementStack[indent] = fnBlock: true
      else if generator.lineMatchesStartBlock(line)
        elementStack[indent] = block: true

  # TEMPLATELINE -> ([ELEMENT][IDSELECTOR][CLASSSELECTORS][ATTRIBUTES] [SLASH|CONTENTS])|(!CONTENTS) (EOL|EOF)
  _templateLine: (tokeniser, elementStack, indent, generator) ->
    haml._closeElements(indent, elementStack, tokeniser, generator) unless tokeniser.token.eol

    identifier = haml._element(tokeniser)
    id = haml._idSelector(tokeniser)
    classes = haml._classSelector(tokeniser)
    objectRef = haml._objectReference(tokeniser)
    attrList = haml._attributeList(tokeniser)

    currentParsePoint = tokeniser.currentParsePoint()
    attributesHash = haml._attributeHash(tokeniser)

    tagOptions =
      selfClosingTag: false
      innerWhitespace: true
      outerWhitespace: true
    lineHasElement = haml._lineHasElement(identifier, id, classes)

    if tokeniser.token.slash
      tagOptions.selfClosingTag = true
      tokeniser.getNextToken()
    if tokeniser.token.gt and lineHasElement
      tagOptions.outerWhitespace = false
      tokeniser.getNextToken()
    if tokeniser.token.lt and lineHasElement
      tagOptions.innerWhitespace = false
      tokeniser.getNextToken()

    if lineHasElement
      if !tagOptions.selfClosingTag
        tagOptions.selfClosingTag = haml._isSelfClosingTag(identifier) and !haml._tagHasContents(indent, tokeniser)
      haml._openElement(currentParsePoint, indent, identifier, id, classes, objectRef, attrList, attributesHash, elementStack,
        tagOptions, generator)
    else if !tokeniser.isEolOrEof() and !tokeniser.token.ws
      tokeniser.pushBackToken()

    hasContents = false
    tokeniser.getNextToken() if tokeniser.token.ws

    if tokeniser.token.equal or tokeniser.token.escapeHtml or tokeniser.token.unescapeHtml
      haml._embeddedJs(tokeniser, indent + 1, null, tagOptions, generator)
      hasContents = true
    else
      contents = ''
      shouldInterpolate = false
      if tokeniser.token.exclamation
        contents = tokeniser.skipToEOLorEOF()
      else if !tokeniser.token.eol
        tokeniser.pushBackToken()
        contents = tokeniser.skipToEOLorEOF()
        contents = contents.substring(1) if contents.match(/^\\%/)
        shouldInterpolate = true

      hasContents = contents.length > 0
      if hasContents
        if tagOptions.innerWhitespace and lineHasElement or (!lineHasElement and haml._parentInnerWhitespace(elementStack, indent))
          indentText = HamlRuntime.indentText(if identifier.length > 0 then indent + 1 else indent)
        else
          indentText = ''
          contents = _(contents).trim()
        generator.appendTextContents(indentText + contents + '\n', shouldInterpolate, currentParsePoint)

    haml._eolOrEof(tokeniser)

    if tagOptions.selfClosingTag and hasContents
      throw haml.HamlRuntime.templateError(currentParsePoint.lineNumber, currentParsePoint.characterNumber,
              currentParsePoint.currentLine, "A self-closing tag can not have any contents")

  _attributeHash: (tokeniser) ->
    attr = ''
    if tokeniser.token.attributeHash
      attr = tokeniser.token.tokenString
      tokeniser.getNextToken()
    attr

  _objectReference: (tokeniser) ->
    attr = ''
    if tokeniser.token.objectReference
      attr = tokeniser.token.tokenString
      tokeniser.getNextToken()
    attr

  # ATTRIBUTES -> ( ATTRIBUTE* )
  _attributeList: (tokeniser) ->
    attrList = {}
    if tokeniser.token.openBracket
      tokeniser.getNextToken()
      until tokeniser.token.closeBracket
        attr = haml._attribute(tokeniser)
        if attr
          attrList[attr.name] = attr.value
        else
          tokeniser.getNextToken()
        if tokeniser.token.ws or tokeniser.token.eol
          tokeniser.getNextToken()
        else if !tokeniser.token.closeBracket and !tokeniser.token.identifier
          throw tokeniser.parseError("Expecting either an attribute name to continue the attibutes or a closing " +
            "bracket to end")
      tokeniser.getNextToken()
    attrList

  # ATTRIBUTE -> IDENTIFIER WS* = WS* STRING
  _attribute: (tokeniser) ->
    attr = null

    if tokeniser.token.identifier
      name = tokeniser.token.tokenString
      tokeniser.getNextToken()
      haml._whitespace(tokeniser)
      throw tokeniser.parseError("Expected '=' after attribute name") unless tokeniser.token.equal
      tokeniser.getNextToken();
      haml._whitespace(tokeniser)
      if !tokeniser.token.string and !tokeniser.token.identifier
        throw tokeniser.parseError("Expected a quoted string or an identifier for the attribute value")
      attr =
        name: name
        value: tokeniser.token.tokenString
      tokeniser.getNextToken()

    attr

  _closeElement: (indent, elementStack, tokeniser, generator) ->
    if elementStack[indent]
      generator.setIndent(indent)
      if elementStack[indent].htmlComment
        generator.outputBuffer.append(HamlRuntime.indentText(indent) + '-->\n')
      else if elementStack[indent].htmlConditionalComment
        generator.outputBuffer.append(HamlRuntime.indentText(indent) + '<![endif]-->\n')
      else if elementStack[indent].block
        generator.closeOffCodeBlock(tokeniser)
      else if elementStack[indent].fnBlock
        generator.closeOffFunctionBlock(tokeniser)
      else
        innerWhitespace = !elementStack[indent].tagOptions or elementStack[indent].tagOptions.innerWhitespace
        if innerWhitespace
          generator.outputBuffer.append(HamlRuntime.indentText(indent))
        else
          generator.outputBuffer.trimWhitespace()
        generator.outputBuffer.append('</' + elementStack[indent].tag + '>')
        outerWhitespace = !elementStack[indent].tagOptions or elementStack[indent].tagOptions.outerWhitespace
        generator.outputBuffer.append('\n') if haml._parentInnerWhitespace(elementStack, indent) and outerWhitespace
      elementStack[indent] = null
      generator.mark()

  _closeElements: (indent, elementStack, tokeniser, generator) ->
    i = elementStack.length - 1
    while i >= indent
      haml._closeElement(i--, elementStack, tokeniser, generator)

  _openElement: (currentParsePoint, indent, identifier, id, classes, objectRef, attributeList, attributeHash, elementStack, tagOptions, generator) ->
    element = if identifier.length == 0 then "div" else identifier

    parentInnerWhitespace = haml._parentInnerWhitespace(elementStack, indent)
    tagOuterWhitespace = !tagOptions or tagOptions.outerWhitespace
    generator.outputBuffer.trimWhitespace() unless tagOuterWhitespace
    generator.outputBuffer.append(HamlRuntime.indentText(indent)) if indent > 0 and parentInnerWhitespace and tagOuterWhitespace
    generator.outputBuffer.append('<' + element)
    if attributeHash.length > 0 or objectRef.length > 0
      generator.generateCodeForDynamicAttributes(id, classes, attributeList, attributeHash, objectRef, currentParsePoint)
    else
      generator.outputBuffer.append(haml.HamlRuntime.generateElementAttributes(null, id, classes, null, attributeList, null,
        currentParsePoint.lineNumber, currentParsePoint.characterNumber, currentParsePoint.currentLine))
    if tagOptions.selfClosingTag
      generator.outputBuffer.append("/>")
      generator.outputBuffer.append("\n") if tagOptions.outerWhitespace
    else
      generator.outputBuffer.append(">")
      elementStack[indent] =
        tag: element
        tagOptions: tagOptions
      generator.outputBuffer.append("\n") if tagOptions.innerWhitespace

  _isSelfClosingTag: (tag) ->
    tag in ['meta', 'img', 'link', 'script', 'br', 'hr']

  _tagHasContents: (indent, tokeniser) ->
    if !tokeniser.isEolOrEof()
      true
    else
      nextToken = tokeniser.lookAhead(1)
      nextToken.ws and nextToken.tokenString.length / 2 > indent

  _parentInnerWhitespace: (elementStack, indent) ->
    indent == 0 or (!elementStack[indent - 1] or !elementStack[indent - 1].tagOptions or elementStack[indent - 1].tagOptions.innerWhitespace)

  _lineHasElement: (identifier, id, classes) ->
    identifier.length > 0 or id.length > 0 or classes.length > 0

  hasValue: (value) ->
    value? && value isnt false

  attrValue: (attr, value) ->
    if attr in ['selected', 'checked', 'disabled'] then attr else value

  _whitespace: (tokeniser) ->
    indent = 0
    if tokeniser.token.ws
      indent = tokeniser.token.tokenString.length / 2
      tokeniser.getNextToken()
    indent

  _element: (tokeniser) ->
    identifier = ''
    if tokeniser.token.element
      identifier = tokeniser.token.tokenString
      tokeniser.getNextToken()
    identifier

  _eolOrEof: (tokeniser) ->
    if tokeniser.token.eol or tokeniser.token.continueLine
      tokeniser.getNextToken()
    else if !tokeniser.token.eof
      throw tokeniser.parseError("Expected EOL or EOF")

  # IDSELECTOR = # ID
  _idSelector: (tokeniser) ->
    id = ''
    if tokeniser.token.idSelector
      id = tokeniser.token.tokenString
      tokeniser.getNextToken()
    id

  # CLASSSELECTOR = (.CLASS)+
  _classSelector: (tokeniser) ->
    classes = []

    while tokeniser.token.classSelector
      classes.push(tokeniser.token.tokenString)
      tokeniser.getNextToken()

    classes

root.haml.Tokeniser = Tokeniser
root.haml.Buffer = Buffer
root.haml.JsCodeGenerator = JsCodeGenerator
root.haml.CoffeeCodeGenerator = CoffeeCodeGenerator
root.haml.HamlRuntime = HamlRuntime
root.haml.filters = filters