-- -*- haskell -*- 
-- Lexer for Makefiles with consideration of GNU extensions 
-- This is based off the syntax as described in the GNU Make manual:
-- http://www.gnu.org/software/make/manual/make.html
--
{
{-# OPTIONS -w  #-}
module Yi.Lexer.GNUMake
  ( initState, alexScanToken ) 
where
import Yi.Lexer.Alex
import Yi.Style
  ( Style             ( .. )
  , StyleName
  )
import qualified Yi.Style as Style
}

@varAssignOp = 
      "="
    | "?="
    | "+="
    | ":="

-- The documentation implies that {,},(, and ) can be used as single character variable names.
-- "A variable name may be any sequence of characters not containing `:', `#', `=', or leading or
-- trailing whitespace."
-- http://www.gnu.org/software/make/manual/make.html#Using-Variables
-- However when I try to feed GNU makefile containing such weird variable names GNU make fails.
-- Though the specification does leave limiting the scope of valid variable names that as an open
-- option for "the future" 
$varChar = $printable # [\: \# \= \ \{ \} \( \)]

@directives = 
      include 
    | if
    | export
    | unexport
    | define

@specialVars = 
      MAKEFILE_LIST
    | ".DEFAULT_GOAL"
    | MAKE_RESTARTS
    | ".VARIABLES"
    | ".FEATURES"
    | ".INCLUDE_DIRS"
    | MAKE

$space = [\ ]

make :-

<0>
{
    -- All lines that start with a \t are passed to the shell post variable expansion and '\'
    -- handling.
    -- TODO: I'm almost convinced I'd like to see the tab character visually distinct from a space.
    -- One possibility would be to treat the tab character as an operator.
    ^\t
        { m (\_ -> RuleCommand) Style.defaultStyle }

    -- There can be any number of spaces (but not tabs!) preceeded a directive.
    ^$space+
        { c Style.defaultStyle }

    -- The "include" directive can occur in two forms:
    --  One preceeded by a "-" 
    --  Another not preceeded by a "-"
    \-?"include"
        { m (\_ -> IncludeDirective) Style.keywordStyle }

    -- A variable expansion outside of a prerequisite can occur in three different forms.
    -- Inside a prerequisite they can occur in four different forms.
    -- TODO: Highlight the automatic variables differently.
    -- 1. Single character variable names unless the character is a $.
    "$$"
        { c Style.defaultStyle }
    \$$varChar
        { c Style.variableStyle }

    -- 2 & 3: Parentheses or brackets could indicate a variable expansion or function call.
    "${"
        { m (\_ -> ComplexExpansion '}') Style.operatorStyle }
    "$(" 
        { m (\_ -> ComplexExpansion ')') Style.operatorStyle }

    \#
        { m (\_ -> InComment) Style.commentStyle }
    \n
        { c Style.defaultStyle }
    .
        { c Style.defaultStyle }
}

-- The include directive is a space separated list. Optionally followed by a comment.
<includeDirective>
{
    $space+
        { c Style.defaultStyle }
    \#
        { m (\_ -> InComment) Style.commentStyle } 
    \n
        { m (\_ -> TopLevel)  Style.defaultStyle }

    -- For now anything else is considered a string.
    -- This is incorrect. The items of the space separated list can be:
    --  0. File globs
    --  1. Variable expansions
    --  2. String literals
    .
        { c Style.stringStyle }
}

-- A variable expansion that starts with a parentheses or bracket could be a function call. For now
-- everything up to the close character is considered part of the variable name.
<complexExpansion>
{
    $white+ { c Style.defaultStyle }
    ./
        {
            \state preInput _ _ ->
                case state of
                    ComplexExpansion endChar ->
                        let currentChar = head $ alexCollectChar preInput
                        in if (currentChar == endChar) then True else False
                    _ -> False
        }
        {
            m (\_ -> TopLevel) Style.operatorStyle
        }
    . 
        { c Style.variableStyle }
}

-- After all the lines joined by a '\' character are appended together the text only undergoes
-- variable expansion before being passed to the shell. 
-- This means that a '#' character only indicates a comment *only* if the shell interpretting the
-- expanded text would consider it a comment. Wack huh?
-- See 3.1
<ruleCommand> 
{
    -- If the \n is preceeded by a \ then the next line is part of this command even if there is no
    -- \t at the start.
    \\[.\n]
        { c Style.makeFileAction }
    \n
        { m (\_ -> TopLevel) Style.defaultStyle }
    $white
        { c Style.defaultStyle }
    .
        { c Style.makeFileAction }
}

<comment>
{
    -- Comments can be continued to the next line with a trailing slash.
    -- See 3.1
    \\[.\n]
        { c Style.commentStyle }
    \n
        { m (\_ -> TopLevel) Style.defaultStyle }
    $white 
        { c Style.defaultStyle }
    .
        { c Style.commentStyle }
}

{
data HlState = 
      TopLevel 
    | InComment
    | IncludeDirective
    | ComplexExpansion Char
    | RuleCommand

stateToInit TopLevel = 0
stateToInit InComment = comment
stateToInit IncludeDirective = includeDirective
stateToInit (ComplexExpansion _) = complexExpansion
stateToInit RuleCommand = ruleCommand

initState :: HlState
initState = TopLevel

type Token = StyleName
#include "alex.hsinc"
}

