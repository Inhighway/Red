REBOL [
	Title:   "Red/System linker"
	Author:  "Nenad Rakocevic"
	File: 	 %linker.r
	Rights:  "Copyright (C) 2011 Nenad Rakocevic. All rights reserved."
	License: "BSD-3 - https://github.com/dockimbel/Red/blob/master/BSD-3-License.txt"
]

linker: context [
	version: 		1.0.0							;-- emitted linker version
	cpu-class: 		'IA-32							;-- default target
	file-emitter:	none							;-- file emitter object
	verbose: 		0								;-- logs verbosity level
	
	line-record!: make-struct [
		ptr		[integer!]							;-- code pointer
		line	[integer!]							;-- line number
		file	[integer!]							;-- filename string offset
	] none
	
	job-class: context [
		format: 									;-- 'PE | 'ELF | 'Mach-o
		type: 										;-- 'exe | 'obj | 'lib | 'dll
		target:										;-- CPU identifier
		sections:									;-- code/data sections
		flags:										;-- global flags
		sub-system:									;-- target environment (GUI | console)
		symbols:									;-- symbols table
		output:										;-- output file name (without extension)
		debug-info:									;-- debugging informations
		buffer: none
	]
	
	resolve-symbol-refs: func [
		job [object!] 
		cbuf [binary!]								;-- code buffer
		dbuf [binary!]								;-- data buffer
		code-ptr [integer!]							;-- code memory address
		data-ptr [integer!]							;-- data memory address
		pointer [object!]
	][
		foreach [name spec] job/symbols [
			unless empty? spec/3 [
				switch spec/1 [
					global [						;-- code to data references
						pointer/value: data-ptr + spec/2
						foreach ref spec/3 [change at cbuf ref form-struct pointer]
					]
					native-ref [					;-- code to code references
						pointer/value: code-ptr + spec/2
						foreach ref spec/3 [change at cbuf ref form-struct pointer]
					]
				]
			]
			if all [	
				spec/1 = 'global
				block? spec/4
			][										;-- data to data references
				pointer/value: data-ptr + spec/2			
				foreach ref spec/4 [change at dbuf ref form-struct pointer]
			]
		]
	]
	
	get-debug-lines-size: func [job [object!] /local size][
		size: 12 * (length? job/debug-info/lines/records) / 3
		foreach file job/debug-info/lines/files [
			size: size + 1 + length? file			;-- file is supposed to be FORMed not MOLDed
		]
		size
	]
	
	build-debug-lines: func [
		job [object!]
		code-ptr [integer!]							;-- code memory address
		pointer [object!]
		/local	records files rec-size buffer table strings record data-buf spec
	][
		records: job/debug-info/lines/records
		files: job/debug-info/lines/files
		
		rec-size: 12 * (length? records) / 3 		;-- 12 = pointer! + integer! + integer!
											 		;--  3 = nb of elements in records (flat structure)
		buffer:  make binary! rec-size		 		;-- main buffer
		table:   make block! length? files	 		;-- intermediary file strings offsets table
		strings: make binary! 32 * length? files	;-- file strings buffer
		
		foreach file files [
			append table length? strings			;-- save file string offsets
			append strings form file
			append strings null
		]
		
		record: make-struct line-record! none
		forskip records 3 [
			record/ptr:  code-ptr + records/1 - 1
			record/line: records/2
			record/file: rec-size + pick table records/3	;-- store file offsets
			append buffer form-struct record
		]
		
		data-buf: job/sections/data/2		
		spec: find job/symbols '__debug-lines
		spec/<data>/2: length? data-buf				;-- patch __debug-lines symbol to point to 1st record
		
		repend data-buf [buffer strings]			;-- append records and strings to data segment
	]
		
	clean-imports: func [imports [block!]][			;-- remove unused imports
		foreach [lib list] imports/3 [
			remove-each [name refs] list [empty? refs]
		]
	]

	make-filename: func [job [object!]][
		rejoin [
			any [job/build-prefix %""]
			job/build-basename
			any [job/build-suffix select file-emitter/defs/extensions job/type]
		]
	]
	
	build: func [job [object!] /local file][
		unless job/target [job/target: cpu-class]
		job/buffer: make binary! 100 * 1024
	
		clean-imports job/sections/import
	
		file-emitter: do rejoin [%formats/ job/format %.r]
		file-emitter/build job

		file: make-filename job
		if verbose >= 1 [print ["output file:" file]]
		write/binary file job/buffer
		
		if find get-modes file 'file-modes 'owner-execute [
			set-modes file [owner-execute: true]
		]
	]

]
