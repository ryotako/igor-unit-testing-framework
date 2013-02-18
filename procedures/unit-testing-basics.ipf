#pragma rtGlobals=3		// Use modern global access method.

StrConstant PKG_FOLDER = "root:Packages:UnitTesting"

ThreadSafe Function/DF GetPackageFolder()
	if( !DataFolderExists(PKG_FOLDER) )
		NewDataFolder/O root:Packages
		NewDataFolder/O root:Packages:UnitTesting
	endif
	
	dfref dfr = $PKG_FOLDER
	return dfr
End

/// Turns debug output on
ThreadSafe Function ENABLE_DEBUG_OUTPUT()
	dfref dfr = GetPackageFolder()
	variable/G dfr:verbose = 1
End

/// Turns debug output off
ThreadSafe Function DISABLE_DEBUG_OUTPUT()
	dfref dfr = GetPackageFolder()
	variable/G dfr:verbose = 0
End

/// Returns 1 if debug output is enabled and zero otherwise
ThreadSafe Function ENABLED_DEBUG()
	dfref dfr = GetPackageFolder()
	NVAR/Z/SDFR=dfr verbose

	if(NVAR_EXISTS(verbose) && verbose == 1)
		return 1
	endif
	return 0
End

/// Debug output for assertions
ThreadSafe Function DEBUG_OUTPUT(str, booleanValue)
	string str
	variable booleanValue
	
	if(ENABLED_DEBUG())
		str += ": is " + SelectString(booleanValue,"false","true")
		print str
	endif
End

/// Create the global_error_count variable and initialize to zero
ThreadSafe Function initGlobalError()
	dfref dfr = GetPackageFolder()
	variable/G dfr:global_error_count = 0
End

/// Create the error_count variable and initialize to zero
ThreadSafe Function initError()
	dfref dfr = GetPackageFolder()
	variable/G dfr:error_count = 0
End

/// Increments the error count, creates the global variable root:error_count if it does not exist
ThreadSafe Function incrError()
	dfref dfr = GetPackageFolder()
	NVAR/Z/SDFR=dfr error_count
	
	if(!NVAR_Exists(error_count))
		initError()
		NVAR/SDFR=dfr error_count
	endif
	
	error_count +=1
End

/// Create the assert_count variable and initialize to zero
ThreadSafe Function initAssertCount()
	dfref dfr = GetPackageFolder()
	variable/G dfr:assert_count = 0
End

/// Increments the assertion count, creates the global variable root:assert_count if it does not exist
ThreadSafe Function incrAssert()
	dfref dfr = GetPackageFolder()
	NVAR/SDFR=dfr/Z assert_count
	
	if(!NVAR_Exists(assert_count))
		initAssertCount()
		NVAR/SDFR=dfr assert_count
		assert_count = 0
	endif
	
	assert_count +=1
End

/// Checks that the current folder is empty
ThreadSafe Function CHECK_EMPTY_FOLDER()
	string folder = ":"
	if ( CountObjects(folder,1) + CountObjects(folder,2) + CountObjects(folder,3) + CountObjects(folder,4)  == 0 )
		// debug out
	else
		incrError()
		printf "folder %s is not empty\r", folder
	endif
End

/// Prints an informative message that the test failed
Function printFailInfo()
	print getInfo(0)
End

/// Prints an informative message that the test suceeded
Function printSuccessInfo()
	print getInfo(1)
End

/// Returns 1 if the abortFlag is set and zero otherwise
ThreadSafe Function shouldDoAbort()
	NVAR/Z/SDFR=GetPackageFolder() abortFlag
	if(NVAR_Exists(abortFlag) && abortFlag == 1)
		return 1
	else
		return 0
	endif
End

/// Sets the abort flag
ThreadSafe Function abortNow()
	dfref dfr = GetPackageFolder()
	variable/G dfr:abortFlag = 1
End

/// Prints an informative message about the test's success or failure
/// It is assumed that the test function CHECK_*_*, REQUIRE_*_*, WARN_*_* is the caller of the calling function, 
/// that means the call stack is e. g. RUN_TEST_SUITE -> testCase -> CHECK_SMALL_VAR -> printFailInfo -> printInfo
static Function/S getInfo(result)
	variable result
	
	string callStack = GetRTStackInfo(3)
//	print callStack

	variable indexThisFunction  = ItemsInList(callStack) - 1 // 0-based indizes
	variable indexCheckFunction = indexThisFunction - 4
	
	if(indexCheckFunction < 0 || indexCheckFunction > indexThisFunction)
		return ""
	endif
	
	string initialCaller 	= StringFromList(indexCheckFunction,callStack,";")
	string procedure		= StringFromList(1,initialCaller,",")
	string line				= StringFromList(2,initialCaller,",")

	// get the line which called the caller of this function
	string procedureContents = ProcedureText("",-1,procedure)
	string text = StringFromList(str2num(line),procedureContents,"\r")
	
	// remove leading and trailing whitespace
	string cleanText
	SplitString/E="^[[:space:]]*(.+?)[[:space:]]*$" text, cleanText

	string errMsg
	sprintf errMsg, "Assertion \"%s\" %s in line %s, procedure \"%s\"\r", cleanText,  SelectString(result,"failed","suceeded"), line, procedure
	return errMsg
End

/// Groups all hooks which are executed at test case/suite begin/end
static Structure TestHooks
	string testBegin
	string testEnd
	string testSuiteBegin
	string testSuiteEnd
	string testCaseBegin
	string testCaseEnd
EndStructure

/// Sets the hooks to the builtin defaults
ThreadSafe static Function setDefaultHooks(hooks)
	Struct TestHooks &hooks
	
	hooks.testBegin      = "TEST_BEGIN"
	hooks.testEnd        = "TEST_END"
	hooks.testSuiteBegin = "TEST_SUITE_BEGIN"
	hooks.testSuiteEnd	  = "TEST_SUITE_END"
	hooks.testCaseBegin  = "TEST_CASE_BEGIN"
	hooks.testCaseEnd	  = "TEST_CASE_END"
End

/// Looks for global override hooks in the module ProcGlobal
static Function getGlobalHooks(hooks)
	Struct TestHooks& hooks

	string userHooks = FunctionList("*_OVERRIDE",";","KIND:2,NPARAMS:1,VALTYPE:1")
	
	variable i
	for(i = 0; i < ItemsInList(userHooks); i+=1)
		string userHook = StringFromList(i,userHooks)
		strswitch(userHook)
			case "TEST_BEGIN_OVERRIDE":
				hooks.testBegin = userHook
				break
			case "TEST_END_OVERRIDE":
				hooks.testEnd = userHook
				break
			case "TEST_SUITE_BEGIN_OVERRIDE":
				hooks.testSuiteBegin = userHook
				break
			case "TEST_SUITE_END_OVERRIDE":
				hooks.testSuiteEnd = userHook
				break
			case "TEST_CASE_BEGIN_OVERRIDE":
				hooks.testCaseBegin = userHook
				break
			case "TEST_CASE_END_OVERRIDE":
				hooks.testCaseEnd = userHook
				break
			default:
				printf "Found unknown override function \"%s\"\r", userHook
				break
		endswitch
	endfor
End

/// Looks for local override hooks in a specific procedure file
static Function getLocalHooks(hooks, procName)
	string procName
	Struct TestHooks& hooks
	
	string userHooks = FunctionList("*_OVERRIDE", ";", "KIND:18,NPARAMS:1,VALTYPE:1,WIN:" + procName)

	variable i
	for(i = 0; i < ItemsInList(userHooks); i+=1)
		string userHook = StringFromList(i,userHooks)
		
		string fullFunctionName = getFullFunctionName(userHook, procName)
		strswitch(userHook)
			case "TEST_SUITE_BEGIN_OVERRIDE":
				hooks.testSuiteBegin = fullFunctionName
				break
			case "TEST_SUITE_END_OVERRIDE":
				hooks.testSuiteEnd = fullFunctionName
				break
			case "TEST_CASE_BEGIN_OVERRIDE":
				hooks.testCaseBegin = fullFunctionName
				break
			case "TEST_CASE_END_OVERRIDE":
				hooks.testCaseEnd = fullFunctionName
				break
			default:
				printf "Found unknown override function \"%s\"\r", userHook
				break
		endswitch
	endfor
End

/// Returns the full name of a function including its module
static Function/S getFullFunctionName(funcName, procName)
	string funcName, procName

	string infoString = FunctionInfo(funcName, procName)
	if(strlen(infoString) <= 0)
		string errMsg
		sprintf errMsg, "Function %s in procedure file %s is unknown\r", funcName, procName
		Abort errMsg
	endif
	string module = StringByKey("MODULE", infoString)
	if(strlen(module) <= 0 )
		module = "ProcGlobal"
	endif
	
	return module + "#" + funcName
End

/// Prototype for test cases
Function TEST_CASE_PROTO()
End

/// Prototype for hook functions
Function USER_HOOK_PROTO(str)
	string str
End

/// Runs all test cases of test suite or just a single test case
/// @param 	testSuiteList	List of procedure files
/// @param 	testCase		(optional) function, one test case, which should be executed only
/// @return					total number of errors 
Function RUN_TEST(testSuiteList, [testName, testCase])
	string testSuiteList, testCase, testName
	
	if(strlen(testSuiteList) <= 0)
		printf "The list of procedure windows is empty\r"
		return NaN
	endif

	variable i, j

	string allProcWindows = WinList("*",";","WIN:128")

	for(i = 0; i < ItemsInList(testSuiteList); i+=1)
		string procWin = StringFromList(i, testSuiteList)
		if(FindListItem(procWin, allProcWindows) == -1)
			printf "A procedure window named %s could not be found.\r", procWin
			return NaN
		endif
	endfor
	
	if(ParamIsDefault(testName))
		testName = "Unnamed"
	endif
	
	struct TestHooks hooks
	// 1.) set the hooks to the default implementations
	SetDefaultHooks(hooks)
	// 2.) get global user hooks which reside in ProcGlobal and replace the default ones
	getGlobalHooks(hooks)

	FUNCREF USER_HOOK_PROTO testBegin	  	  = $hooks.testBegin
	FUNCREF USER_HOOK_PROTO testEnd	      = $hooks.testEnd

	testBegin(testName)
	
	variable abortNow = 0
	for(i = 0; i < ItemsInList(testSuiteList); i+=1)
	
		procWin = StringFromList(i, testSuiteList)
	
		string testCaseList
		if(ParamIsDefault(testCase))
			// 18 == 16 (static function) or 2 (userdefined functions)
			testCaseList = FunctionList("!*_IGNORE",";","KIND:18,NPARAMS:0,WIN:" + procWin)
		else
			testCaseList = testCase
		endif

		struct TestHooks procHooks
		procHooks = hooks
		// 3.) get local user hooks which reside in the same Module as the requested procedure
		getLocalHooks(procHooks, procWin)
		
		FUNCREF USER_HOOK_PROTO testSuiteBegin = $procHooks.testSuiteBegin
		FUNCREF USER_HOOK_PROTO testSuiteEnd   = $procHooks.testSuiteEnd
		FUNCREF USER_HOOK_PROTO testCaseBegin	  = $procHooks.testCaseBegin
		FUNCREF USER_HOOK_PROTO testCaseEnd	  = $procHooks.testCaseEnd
		
		testSuiteBegin(procWin)
	
		for(j = 0; j < ItemsInList(testCaseList); j += 1)
			string funcName = StringFromList(j,testCaseList)
			string fullFuncName = getFullFunctionName(funcName, procWin)
			
			FUNCREF TEST_CASE_PROTO testCaseFunc = $fullFuncName
		
			testCaseBegin(funcName)
			testCaseFunc()
			testCaseEnd(funcName)

			if( shouldDoAbort() )
				break
			endif
		endfor
	
		testSuiteEnd(procWin)

		if( shouldDoAbort() )
			break
		endif
	endfor
	
	testEnd(testName)
	
	NVAR/SDFR=GetPackageFolder() error_count
	return error_count
End