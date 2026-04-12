.intel_syntax noprefix
.data
	header:
		.asciz "HTTP/1.0 200 OK\r\n\r\n"
	get_st:  .ascii "GET "
	post_st:  .asciz "POST"
	isforked: .space 1
	sockaddr: 
		.byte 0x02,0x00                               # sin_family = AF_INET
		.byte 0x00,0x50                               # sin_port   = 80
		.byte 0x00,0x00,0x00,0x00                     # sin_addr   = 0.0.0.0
		.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 # padding
	sigign:
    	.quad 1    # sa_handler = SIG_IGN
    	.quad 0    # sa_flags
    	.quad 0    # sa_restorer
    	.quad 0    # sa_mask (128 bits = 2 quads... actually need 16 bytes)
    	.quad 0
	reuseaddr_val: .long 1
.bss
	socket_fd: .space 2
.text
.global _start

_start:
	# create a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	mov rax, 41
	syscall

	mov word ptr [socket_fd], ax # store the socket fd

	# mov rdi, 17          # SIGCHLD
    # lea rsi, [sigign]    # pointer to sigaction struct
    # xor rdx, rdx         # NULL oldact
    # mov r10, 8           # sigsetsize
    # mov rax, 13          # rt_sigaction
    # syscall
	
	# mov rdi, qword ptr [socket_fd]
    # mov rsi, 1       # SOL_SOCKET
    # mov rdx, 2       # SO_REUSEADDR
    # lea r10, [reuseaddr_val]
    # mov r8, 4
    # mov rax, 54      # setsockopt
    # syscall

	### Even though stack grows downwards,
	### data writing and reading is always done
	### from lower addresses to higher addresses.

	# creating the sockaddr object on stack
	push rbp
	mov rbp, rsp
	sub rsp, 1   # 1   for isforked     (-1)
	sub rsp, 2   # 2   for conn_fd      (-3)
	sub rsp, 500 # 300 for request_data (-503)
	sub rsp, 8   # 8   for request_size (-511+44)
	sub rsp, 8   # 8   for post_off     (-519)
	sub rsp, 2   # 2   for file_fd      (-521)
	sub rsp, 100 # 100 for file_name    (-621)
	sub rsp, 256 # 256 for file_data    (-877)

	mov byte ptr [rbp-1], 0 # set isforked

	# sockaddr object
	# mov word ptr [rbp-16], 0x0002      # sin_family
	# mov word ptr [rbp-14], 0x5000      # sin_port
	# mov dword ptr [rbp-12], 0x00000000 # sin_addr

	# bind the socket
	movzx rdi, word ptr [socket_fd]  # move the socket fd to rdi
	lea rsi, [sockaddr]
	mov rdx, 16
	mov rax, 49
	syscall

	# listen on the bound port
	movzx rdi, word ptr [socket_fd]
	mov rsi, 0
	mov rax, 50
	syscall

	# Accept the connections iteratively
	mainloop:
		# accept incoming connections
		mov rdi, qword ptr [socket_fd]
		mov rsi, 0
		mov rdx, 0
		mov rax, 43
		syscall

		# check for error and run the loop until theres a new connection
		test rax, rax
		js mainloop

		# store the fd for the connection
		mov word ptr [rbp-3], ax

		# fork the process from here
		mov rax, 57
		syscall

		# if this is not a child process, then dont process any request
		# i.e. jump to done, else stay and process.
		# Also, set a flag so as to make sure that the child process
		# exits instead of trying to accept requests on its own.
		cmp rax, 0
		jne done
		mov byte ptr [rbp-1], 1

		# close the socket fd so that we dont accidentally touch it
		movzx rdi, word ptr [socket_fd]
		mov rax, 3
		syscall

		# read the request
		movzx rdi, word ptr [rbp-3]
		lea rsi, [rbp-503]
		mov rdx, 500
		mov rax, 0
		syscall

		mov qword ptr [rbp-511], rax

		mov eax, dword ptr [get_st]
		cmp dword ptr [rbp-503], eax
		je GET

		mov eax, dword ptr [post_st]
		cmp dword ptr [rbp-503], eax
		je POST
		jmp done
		
		GET:
			# extract the requested path from the request
			mov rdx, 100
			mov rcx, 0
			loop:
				cmp rcx, rdx
				je endloop
				cmp byte ptr [rbp-503+4+rcx], 0x20
				je endloop
				mov al, byte ptr [rbp-503+4+rcx]
				mov byte ptr [rbp-621+rcx], al
				inc rcx
				jmp loop
			endloop:
			mov byte ptr [rbp-621+rcx], 0

			# open the file requested
			lea rdi, [rbp-621]
			mov rsi, 0
			mov rax, 2
			syscall

			# check if the file even exists
			test rax, rax
    		js done

			mov word ptr [rbp-521], ax # store the fd

			# read the file data
			movzx rdi, word ptr [rbp-521]
			lea rsi, [rbp-877]
			mov rdx, 256
			mov rax, 0
			syscall

			# read the file data size
			mov rbx, rax
			
			# close the fd
			movzx rdi, word ptr [rbp-521]
			mov rax, 3
			syscall
			
			# send the header
			movzx rdi, word ptr [rbp-3]
			lea rsi, header
			mov rdx, 19
			mov rax, 1
			syscall
			
			# send the file data
			movzx rdi, word ptr [rbp-3]
			lea rsi, [rbp-877]
			mov rdx, rbx
			mov rax, 1
			syscall

			jmp done
		POST:
			# extract the requested path from the request
			mov rdx, 100
			mov rcx, 0
			loop2:
				cmp rcx, rdx
				je endloop2
				cmp byte ptr [rbp-503+5+rcx], 0x20
				je endloop2
				mov al, byte ptr [rbp-503+5+rcx]
				mov byte ptr [rbp-621+rcx], al
				inc rcx
				jmp loop2
			endloop2:
			mov byte ptr [rbp-621+rcx], 0

			# find the offset for content to write
			mov rcx, 0
			loop3:
				cmp rcx, qword ptr [rbp-511]
				je endloop3
				cmp byte ptr [rbp-503+rcx], 0x0d
				jne next3
				cmp byte ptr [rbp-503+rcx+1], 0x0a
				jne next3
				cmp byte ptr [rbp-503+rcx+2], 0x0d
				jne next3
				cmp byte ptr [rbp-503+rcx+3], 0x0a
				jne next3
				add rcx, 4
				jmp endloop3
			next3:
				inc rcx
				jmp loop3
			endloop3:

			# store post data offset
			mov qword ptr [rbp-519], rcx

			# open the file requested
			lea rdi, [rbp-621]
			mov rsi, 0x41  # set the O_WRONLY(0b1) | O_CREAT flag (0b1000000)
			mov rdx, 0x1ff # filemodee = 777 (rwx for all)
			mov rax, 2
			syscall
			
			mov word ptr [rbp-521], ax # store the fd
			
			# load back post data offset
			mov rcx, qword ptr [rbp-519]

			# write to the fd
			movzx rdi, word ptr [rbp-521]
			lea rsi, [rbp-503+rcx]
			mov rax, qword ptr [rbp-511]
			sub rax, rcx
			mov rdx, rax
			mov rax, 1
			syscall

			# close the fd
			movzx rdi, word ptr [rbp-521]
			mov rax, 3
			syscall
		
			# send ok response
			movzx rdi, word ptr [rbp-3]
			lea rsi, header
			mov rdx, 19
			mov rax, 1
			syscall
		done:
			cmp byte ptr [rbp-1], 1
			je exit
			# close the conenction after sending the response or in the parent
			movzx rdi, word ptr [rbp-3]
			mov rax, 3
			syscall
			jmp mainloop
	# return the stack to previous point
exit:
	mov rsp, rbp
	pop rbp
	# exit the program
	mov rdi, 0
	mov rax, 60
	syscall
