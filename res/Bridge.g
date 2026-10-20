grammar Bridge;

options {
  language = Java;
  output = AST;
}

tokens { VARIABLE_NAME; GLOBAL_VARIABLE; SYSTEM_BID_NODE; PARNERSHIP_BID; SYSTEM_BID_DEFNS; SYSTEM_BID_DEFN; FIXED_BID; VARIABLE_BID; BID_RANGE; BID_LIST; BID_STEP; BID_ANY;
SYSTEM_BID_GROUP; CONTINUATION_ID; LAST_BID_PARAM; REPLACE_PARAM; SELECTOR_PARAM; SHAPE_CONSTRAINT; DIST_CONSTRAINT; VAR_BID_DEFN; VAR_BID_CONST; 
HCP_CONSTRAINT; MIN_CONSTRAINT; MAX_CONSTRAINT; SUIT_LEN_CONSTRAINT; RELATIVE_LEN_CONSTRAINT; SUIT_QUALITY_MIN_CONSTRAINT; SUIT_QUALITY_MAX_CONSTRAINT; 
NAMED_CARD_CONSTRAINT; NOT_NODE; OR_NODE; AND_NODE; SUIT_SELECTOR_SUIT; BID_DEFN; QUALIFIER_NODE; PRIORITY_NODE; QUALIFIED_SYSTEM_BID_DEFN; NAMED_CONTINUATION_PARAM;
SUIT_SELECTOR_VAR; SUIT_SELECTOR_PERCENT; SUIT_SELECTOR_ANY; SUIT_SELECTOR_UNDEFINED; SYSTEM_BID_CHOOSER; SYSTEM_BID_CHOOSER_OPTION; NAMED_CONTINUATION; EMBEDDED_CONTINUATION;
SYSTEM_BID_DESC; PRACTICE_LEVEL; SYSTEM_BID_NAME_DEFN; SYSTEM_BID_NAME; PERCENTAGE; CONTEXT_NODE; SYSTEM_BID_DEFN_QUALIFIER; SYSTEM_BID_LINE; COND_CONTINUATION; COND_CONTINUATION_DEFN;
COND_SYSTEM_BID_DEFN; BID_GROUP_ID; COND_CONTINUATION_IDS; SYSTEM_BIDS; KNR_CONSTRAINT; CONCENTRATED_CONSTRAINT; } // imaginary token

@header {
  package com.josulasa.bridge.grammar;
}
@lexer::header {
  package com.josulasa.bridge.grammar;
}

@members{
  private int systemBidNo;
  private Stack<String> systemBidName = new Stack<String>();
  
  private String stripQuotes(final String quotedString) {
    if (quotedString != null && quotedString.length() > 1 && quotedString.charAt(0) == '\"' && quotedString.charAt(quotedString.length()-1) == '\"') {
      return quotedString.substring(1, quotedString.length()-1);
    }
    return quotedString;
  }
}

system: header variables systemDefn;

header: SYSTEM COLON STRING_LITERAL PLAYER COLON STRING_LITERAL PARTNER COLON STRING_LITERAL; 

variables : 'BidDefinitions' LEFT_SQUARE variable* RIGHT_SQUARE;

variable: LEFT_PAREN variableName COMMA variableBidDefns RIGHT_PAREN -> ^(GLOBAL_VARIABLE variableName variableBidDefns);

variableName: DOLLAR nn=numberName -> ^(VARIABLE_NAME[$nn.text]);

numberName:(NAME|(NUMBER NAME));

variableBidDefns
scope { int vbdCount; }
: variableBidDefn {$variableBidDefns::vbdCount=1;} (COMMA variableBidDefn {$variableBidDefns::vbdCount++;})* 
    -> {$variableBidDefns::vbdCount==1}? variableBidDefn+
    -> ^(OR_NODE variableBidDefn+)
;

variableBidDefn
scope { int nvbcCount; }
@init {
  $variableBidDefn::nvbcCount = 0;
}
: (negatableVariableBidConstraint {$variableBidDefn::nvbcCount++;} )+ 
-> {$variableBidDefn::nvbcCount>1}? ^(VAR_BID_DEFN ^(AND_NODE negatableVariableBidConstraint+))
-> ^(VAR_BID_DEFN negatableVariableBidConstraint+);

negatableVariableBidConstraint: a=NOT? variableBidConstraint 
  -> {a==null}? ^(VAR_BID_CONST variableBidConstraint)
  -> ^(NOT_NODE ^(VAR_BID_CONST variableBidConstraint))
;

variableBidConstraint: variableName|hcpConstraint|knrConstraint|suitLengthConstraint|shapeConstraint|distributionConstraint|relativeLengthConstraint|suitQualityConstraint|namedCardsConstraint|concentratedValues;

hcpConstraint: a=pointsDefn HCP -> ^(HCP_CONSTRAINT ^(MIN_CONSTRAINT[$a.minOut]) ^(MAX_CONSTRAINT[$a.maxOut]));

knrConstraint: a=pointsDefn KNR -> ^(KNR_CONSTRAINT ^(MIN_CONSTRAINT[$a.minOut]) ^(MAX_CONSTRAINT[$a.maxOut]));

pointsDefn returns [String minOut, String maxOut]: r=range{$minOut=$r.minOut; $maxOut=$r.maxOut;}|r1=equals{$minOut=$r1.minOut; $maxOut=$r1.maxOut;}|r2=lessThanOrEquals["0"]{$minOut=$r2.minOut; $maxOut=$r2.maxOut;}|r3=greaterThanOrEquals["37"] {$minOut=$r3.minOut; $maxOut=$r3.maxOut;};

suitLengthConstraint: a=lengthDefn s=suitSelector -> ^(SUIT_LEN_CONSTRAINT MIN_CONSTRAINT[$a.minOut] MAX_CONSTRAINT[$a.maxOut] $s);

suitQualityConstraint: q=QUALITY_RULE (p=PLUS|d=DASH) suitSelector 
    -> {p!=null}? ^(SUIT_QUALITY_MIN_CONSTRAINT[$q.text] suitSelector)
    -> ^(SUIT_QUALITY_MAX_CONSTRAINT[$q.text] suitSelector)
;

namedCardsConstraint:n=NAMED_CARD_RULE suitSelector -> ^(NAMED_CARD_CONSTRAINT[$n.text] suitSelector); 

concentratedValues:CONCENTRATED LEFT_CURLY suitSelector (COMMA suitSelector)* RIGHT_CURLY -> ^(CONCENTRATED_CONSTRAINT suitSelector+);

suitSelector: (s=SUITS|v=variableName|p=PERCENT|d=DISTRIBUTION)  
      -> {s!=null}? ^(SUIT_SELECTOR_SUIT[$s])
      -> {v!=null}? ^(SUIT_SELECTOR_VAR $v)
      -> {p!=null}? ^(SUIT_SELECTOR_PERCENT[$p])
      -> ^(SUIT_SELECTOR_ANY[$d])
;

lengthDefn returns [String minOut, String maxOut]: r1=equals{$minOut=$r1.minOut; $maxOut=$r1.maxOut;}|r2=lessThanOrEquals["0"]{$minOut=$r2.minOut; $maxOut=$r2.maxOut;}|r3=greaterThanOrEquals["13"] {$minOut=$r3.minOut; $maxOut=$r3.maxOut;};

intLiteral: value=NUMBER;
doubleLiteral: NUMBER'.'NUMBER;
numericLiteral: intLiteral | doubleLiteral;

range returns [String minOut, String maxOut]: r1=numericLiteral DASH r2=numericLiteral {$minOut=$r1.text; $maxOut=$r2.text;};
equals returns [String minOut, String maxOut]: r1=numericLiteral {$minOut=$r1.text; $maxOut=$r1.text;};
lessThanOrEquals[String minIn] returns [String minOut, String maxOut]: r1=numericLiteral DASH {$minOut=$minIn; $maxOut=$r1.text;};
greaterThanOrEquals[String maxIn] returns [String minOut, String maxOut]:  r1=numericLiteral PLUS {$minOut=$r1.text; $maxOut=$maxIn;};

shapeConstraint: a=SHAPE_RULE -> ^(SHAPE_CONSTRAINT $a);

distributionConstraint: a=DIST_RULE -> ^(DIST_CONSTRAINT $a);

relativeLengthConstraint: suitSelector lengthComparator suitSelector -> ^(RELATIVE_LEN_CONSTRAINT suitSelector lengthComparator suitSelector);

lengthComparator: ASSIGN|LESS_THAN|LESS_THAN_OR_EQUALS|GREATER_THAN|GREATER_THAN_OR_EQUALS;

systemDefn: oppositionOpening opening systemFragments; 

oppositionOpening: a=OPPOSITIONOPENING LEFT_SQUARE {systemBidName.push($a.text);} systemBids {systemBidName.pop();} RIGHT_SQUARE;

opening: a=OPENING LEFT_SQUARE {systemBidName.push($a.text);} systemBids {systemBidName.pop();} RIGHT_SQUARE;

systemFragments: FRAGMENTS LEFT_SQUARE systemFragment* RIGHT_SQUARE;

systemFragment: FRAGMENT a=fragmentName LEFT_SQUARE {systemBidName.push(stripQuotes($a.text));} systemBids {systemBidName.pop();} RIGHT_SQUARE;

fragmentName: NAME;

systemBids: systemBidBlock* -> ^(SYSTEM_BIDS systemBidBlock*);  //^(CONTINUATION_ID systemBidContinuations?)

systemBidBlock: condtionalLine ->^(COND_CONTINUATION SYSTEM_BID_GROUP[systemBidName.peek()] condtionalLine) | systemBidLine ->^(SYSTEM_BID_LINE systemBidLine);

condtionalLine: conditionalContinuation {systemBidName.push("I"+systemBidNo++); } systemBidContinuations  {systemBidName.pop();};

systemBidLine
: systemBid systemBidContinuations?;

systemBid
scope { boolean partnership; }
: systemBidChooser? systemBidName COLON systemBidDesc? systemBidDefns? practiceLevel?
-> ^(SYSTEM_BID_NODE PARNERSHIP_BID[String.valueOf($systemBid::partnership)] SYSTEM_BID_GROUP[systemBidName.peek()] systemBidName systemBidChooser? systemBidDesc? systemBidDefns? practiceLevel?  );

conditionalContinuation: CONDITIONAL_LINK systemBidDesc? conditions -> ^(COND_CONTINUATION_DEFN systemBidDesc? conditions);

conditions: LEFT_PAREN systemBidDefn RIGHT_PAREN -> ^(COND_SYSTEM_BID_DEFN systemBidDefn);

systemBidChooser
scope { int sbcCount; }
: LESS_THAN systemBidChooserOption {$systemBidChooser::sbcCount=1;}  (COMMA systemBidChooserOption {$systemBidChooser::sbcCount++;})* GREATER_THAN 
    -> {$systemBidChooser::sbcCount==1}? ^(SYSTEM_BID_CHOOSER systemBidChooserOption)+
    -> ^(SYSTEM_BID_CHOOSER ^(AND_NODE systemBidChooserOption+))
;

systemBidChooserOption: a=NOT? variableName ASSIGN systemBidChooserSuitSelector
  -> {a==null}? ^(SYSTEM_BID_CHOOSER_OPTION variableName systemBidChooserSuitSelector)
  -> ^(NOT_NODE ^(SYSTEM_BID_CHOOSER_OPTION variableName systemBidChooserSuitSelector))
  ;
  
systemBidChooserSuitSelector: (s=SUITS|u=UNDEFINED|p=PERCENT)  
      -> {s!=null}? ^(SUIT_SELECTOR_SUIT[$s])
      -> {p!=null}? ^(SUIT_SELECTOR_PERCENT[$p])
      -> ^(SUIT_SELECTOR_UNDEFINED $u)
;

systemBidDesc: s=STRING_LITERAL -> ^(SYSTEM_BID_DESC[$s]);

systemBidName: oppoSystemBidName|partnershipSystemBidName;

oppoSystemBidName: LEFT_PAREN percentage? qualifier? systemBidNameDefn RIGHT_PAREN {$systemBid::partnership = false;} -> ^(SYSTEM_BID_NAME ^(SYSTEM_BID_NAME_DEFN systemBidNameDefn) qualifier? percentage?);

partnershipSystemBidName: qualifier? systemBidNameDefn {$systemBid::partnership = true;} -> ^(SYSTEM_BID_NAME ^(SYSTEM_BID_NAME_DEFN systemBidNameDefn) qualifier?);

systemBidNameDefn: bridgeBid|bidRange|bidSet|bidStep|bidAny;

bidAny: DISTRIBUTION -> ^(BID_ANY);

bridgeBid: fixedBid|variableBid;

bidRange: LEFT_SQUARE a=bridgeBid DASH b=bridgeBid RIGHT_SQUARE -> ^(BID_RANGE $a $b);

bidSet: LEFT_SQUARE bridgeBid (COMMA bridgeBid)* RIGHT_SQUARE -> ^(BID_LIST bridgeBid*);

bidStep: LEFT_SQUARE a=bidStepSize RIGHT_SQUARE -> ^(BID_STEP[$a.text]);

bidStepSize : NUMBER;

variableBid: NUMBER variableName -> ^(VARIABLE_BID NUMBER variableName);

fixedBid: ((NUMBER (SUITS|NO_TRUMPS))|NON_SUITBIDS) -> ^(FIXED_BID[$fixedBid.text]);

percentage: n=NUMBER PERCENT -> ^(PERCENTAGE[$n]);

systemBidDefns
scope { int sbdCount; }
: LEFT_PAREN qualifiedSystemBidDefn {$systemBidDefns::sbdCount=1;} (CARET qualifiedSystemBidDefn {$systemBidDefns::sbdCount++;} )* RIGHT_PAREN 
-> {$systemBidDefns::sbdCount==1}?  ^(SYSTEM_BID_DEFNS qualifiedSystemBidDefn)
-> ^(SYSTEM_BID_DEFNS ^(OR_NODE qualifiedSystemBidDefn+))
| LEFT_PAREN systemBidDefn RIGHT_PAREN -> ^(SYSTEM_BID_DEFNS systemBidDefn)
;

qualifiedSystemBidDefn:
systemBidQualifier systemBidDefn->^(QUALIFIED_SYSTEM_BID_DEFN systemBidQualifier systemBidDefn)
;

systemBidDefn:
bidDefns context? ->^(SYSTEM_BID_DEFN bidDefns context?)
;

bidDefns
scope { int bdCount; }
: bidDefn {$bidDefns::bdCount=1;} (COMMA bidDefn {$bidDefns::bdCount++;})*
    -> {$bidDefns::bdCount==1}? ^(BID_DEFN bidDefn)*
    -> ^(OR_NODE ^(BID_DEFN bidDefn)+)
;

bidDefn
scope { int nvbcCount; }
@init {
  $bidDefn::nvbcCount = 0;
}
: priority? (negatableVariableBidConstraint {$bidDefn::nvbcCount++;})*
-> {$bidDefn::nvbcCount==0}? priority? ^(VAR_BID_DEFN)
-> {$bidDefn::nvbcCount==1}? priority? ^(VAR_BID_DEFN (negatableVariableBidConstraint)*)
-> priority? ^(AND_NODE negatableVariableBidConstraint*);

systemBidQualifier:bridgeBid COLON -> ^(SYSTEM_BID_DEFN_QUALIFIER bridgeBid);

context: LEFT_SQUARE contextVariable (COMMA contextVariable)* RIGHT_SQUARE -> ^(CONTEXT_NODE contextVariable)+;

contextVariable: variableName ASSIGN variableValue -> variableName variableValue;

variableValue: p=PERCENT -> ^(SUIT_SELECTOR_PERCENT[$p])
|s=SUITS -> ^(SUIT_SELECTOR_SUIT[$s])
|u=UNDEFINED -> ^(SUIT_SELECTOR_UNDEFINED[$u])
|bidDefn -> ^(BID_DEFN bidDefn);

priority: p=PRIORITY_RULE -> ^(PRIORITY_NODE[$p.text.substring(2)]);

qualifier: (NAME (DOT STRING_LITERAL)* DOT) -> ^(QUALIFIER_NODE[$qualifier.text.substring(0, $qualifier.text.length()-1)]);

practiceLevel: QUESTION_MARK n=NUMBER ->^(PRACTICE_LEVEL[$n.text]);

systemBidContinuations
:
namedContinuation
-> ^(CONTINUATION_ID ^(NAMED_CONTINUATION[$namedContinuation.value] namedContinuation) )
| embeddedSystemBids
-> ^(CONTINUATION_ID ^(EMBEDDED_CONTINUATION[$embeddedSystemBids.value] embeddedSystemBids))
;

namedContinuation returns [String value]: LINK a=NAME namedContinuationParam? {$value=stripQuotes($a.text);} -> ^(NAMED_CONTINUATION_PARAM namedContinuationParam?);

namedContinuationParam: lastBidParam|replaceParam|selectorParam;

lastBidParam: LASTBID COLON bridgeBid -> ^(LAST_BID_PARAM bridgeBid);

replaceParam: REPLACE COLON a=bridgeBid LINK b=bridgeBid -> ^(REPLACE_PARAM $a $b);

selectorParam: SELECTOR COLON variableName -> ^(SELECTOR_PARAM variableName);

embeddedSystemBids returns [String value]: LEFT_CURLY a=namedSystemBid? {if(a==null) $value="I"+systemBidNo++; else $value=$a.value; systemBidName.push($value); } systemBids {systemBidName.pop();} RIGHT_CURLY;

namedSystemBid returns [String value]: NAMED_SEQN  a=systemBidAlias {$value=$a.text;};

systemBidAlias : NAME;

bidDesc: STRING_LITERAL;


APOSTROPHE: '\''; // for derivative
ASSIGN: '=';
CARET: '^'; // for exponentiation
COLON: ':';
COMMA: ',';
DASH: '-';
DOLLAR: '$';
DOT: '.';
FUNCTIONS: 'functions'; // for list command
HCP: 'hcp';
KNR: 'knr';
QUESTION_MARK: '?';
LESS_THAN_OR_EQUALS: '<=';
GREATER_THAN_OR_EQUALS: '>=';
LESS_THAN: '<';
GREATER_THAN: '>';
LEFT_CURLY: '{';
LEFT_PAREN: '(';
LEFT_SQUARE: '[';
LINK: '->';
CONDITIONAL_LINK: '~>';
LIST: 'list';
NOT: '!';
OR: '|';
NAMED_SEQN: 'name';
PARTNER: 'Partner';
PERCENT: '%';
PLAYER: 'Player';
PLUS: '+';
PRIORITY: 'p' INTEGER;
PRINT: 'print';
RIGHT_PAREN: ')';
RIGHT_SQUARE: ']';
RIGHT_CURLY: '}';
SYSTEM: 'System';
VARIABLES: 'variables'; // for list command
DISTRIBUTION: '*';
NON_SUITBIDS: PASS|DBL|RDBL;
NO_TRUMPS: 'nt';
SUITS: CLUBS|DIAMONDS|HEARTS|SPADES;
UNDEFINED: 'undef';
ANYLENGTH: 'x';
OPPOSITIONOPENING: 'OppositionOpeningBids';
OPENING: 'OpeningBids';
LASTBID: 'lastBid';
REPLACE: 'replace';
SELECTOR: 'selector';
FRAGMENTS: 'Fragments';
FRAGMENT: 'Fragment';
QUALITY_DEFN: 'q' ('H'|'h')*;
NAMED_CARD_DEFN: 'n' ('a'|'A'|'k'|'K'|'q'|'Q')+ (OR ('a'|'A'|'k'|'K'|'q'|'Q')+)*;
CONCENTRATED:'con';
ML_COMMENT
    :   '/*' (options {greedy=false;} : .)* '*/' {$channel=HIDDEN;}
    ;
SHAPE: 's'(INTEGER|ANYLENGTH)+ (OR (INTEGER|ANYLENGTH)+)*;
DIST: 'd'(INTEGER|ANYLENGTH)+ (OR (INTEGER|ANYLENGTH)+)*;

NUMBER: INTEGER;
fragment INTEGER: '0'..'9'+;
NAME: LETTER (LETTER | DIGIT | '_')*;
STRING_LITERAL: '"' NONCONTROL_CHAR* '"';

fragment NONCONTROL_CHAR: LETTER | DIGIT | SYMBOL | SPACE;
fragment LETTER: LOWER | UPPER;
fragment LOWER: 'a'..'z';
fragment UPPER: 'A'..'Z';
fragment DIGIT: '0'..'9';
fragment SPACE: ' ' | '\t';
fragment CLUBS: 'c';
fragment DIAMONDS: 'd';
fragment HEARTS: 'h';
fragment SPADES: 's';
fragment PASS: 'pass';
fragment DBL: 'dbl';
fragment RDBL: 'rdbl';
PRIORITY_RULE: 'p#' NUMBER;
SHAPE_RULE: 's#'(INTEGER|ANYLENGTH)+ (OR (INTEGER|ANYLENGTH)+)*;
DIST_RULE: 'd#'(INTEGER|ANYLENGTH)+ (OR (INTEGER|ANYLENGTH)+)*;
QUALITY_RULE: 'q#' ('H'|'h')*;
NAMED_CARD_RULE: 'n#' NAMED_CARDS;
fragment NAMED_CARDS: ('a'|'A'|'k'|'K'|'q'|'Q')+ ('|' ('a'|'A'|'k'|'K'|'q'|'Q')+)*;

//fragment DASH: '-';

// Note that SYMBOL does not include the double-quote character.
fragment SYMBOL: '!' | '#'..'/' | ':'..'@' | '['..'`' | '{'..'~';

// Windows uses \r\n. UNIX and Mac OS X use \n.
// To use newlines as a terminator,
// they can't be written to the hidden channel!
//NEWLINE: ('\r'? '\n')+;
//WHITESPACE: SPACE+ { $channel = HIDDEN; };
WHITESPACE  : (' '|'\r'|'\t'|'\n')+{ $channel = HIDDEN; };

