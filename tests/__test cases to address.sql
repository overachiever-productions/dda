/*


	Things to test within dda.get_audit_data: 


	A. Errors/Exceptions for various scenarios I've accounted for up-front. 
		i.e., exceptions for param verification/etc. 


	B. Mappings
		Make sure that dda.translation_xxx stuff works. 
		MAKE SURE that dda.translation_xxx stuff is NOT case sensitive. 

		Makes sure that dda.surrogate_keys stuff works
			-> that we'll get a mapping if it's there. 
			-> that case doesn't matter. 
			-> that we throw an EXCEPTION? really? if there's no mapping. 
				Yeah. I should be protecting against this stuff in CAPTURE, but ... can't really deal with it during translation either... 
					and... maybe an exception is too 'big' - maybe throw a warning? 

					ACTUALLY. My initial test in [transformations].[test ensure_translation_output]
					shows that I can simply NOT load this info... i.e., these mappings are NOT needed for SEARCh/OUTPUT
						which, duh, makes sense. they're ONLY needed to order data for the capture. Search is 'static'-ish.


	C. Pagination & Filters/Predication.



	D. Translations
		Specific Translations that I might care about. 
		But, mostly, that if I put in A and run everything through the sproc, I get A' back out - exactly/faithfully/NO-DEVIATIONS. 


		Similar to [transformations].[test ensure_translation_output]
			use ... tSQLt.AssertEqualsTable 
				to check things like: 
					audit_ids, 
					row_numbers, 
					users
					tables
					operation types
					row_counts
					etc... 

					(otherwise, the test above -> [transformations].[test ensure_translation_output] - is for JSON verification only).







*/