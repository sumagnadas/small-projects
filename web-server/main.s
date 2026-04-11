.intel_syntax noprefix
.data
	header:
		.asciz "HTTP/1.0 200 OK\r\n\r\n"
	get_st:  .ascii "GET "
	post_st:  .asciz "POST"
	isforked: .space 1
.bss
	filename: .space 100
	request_data: .space 256
	post_off: .space 8
	file_data: .space 256
	socket_fd: .space 8
	conn_fd: .space 8
	file_fd: .space 8
	request_size: .space 8
.text
.global _start

_start:
	# create a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	mov rax, 41
	syscall

	### Even though stack grows downwards,
	### data writing and reading is always done
	### from lower addresses to higher addresses.

	# creating the sockaddr object on stack
	push rbp
	mov rbp, rsp
	sub rsp, 16 # 16 for sockaddr

	mov word ptr [socket_fd], ax # store the socket fd
	# sockaddr object
	mov word ptr [rbp-16], 0x0002      # sin_family
	mov word ptr [rbp-14], 0x5000      # sin_port
	mov dword ptr [rbp-12], 0x00000000 # sin_addr

	# bind the socket
	mov rdi, qword ptr [socket_fd]  # move the socket fd to rdi
	lea rsi, [rbp-16]
	mov rdx, 16
	mov rax, 49
	syscall

	# listen on the bound port
	mov rdi, qword ptr [socket_fd]
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

		# store the fd for the connection
		mov word ptr [conn_fd], ax

		# fork the process from here
		mov rax, 57
		syscall

		# if this is not a child process, then dont process any reques
		# i.e. jump to done, else stay and process.
		# Also, set a flag so as to make sure that the child process
		# exits instead of trying to accept requests on its own.
		cmp rax, 0
		jne done
		mov byte ptr [isforked], 1

		# close the socket fd so that we dont accidentally touch it
		mov rdi, qword ptr [socket_fd]
		mov rax, 3
		syscall

		# read the request
		mov rdi, qword ptr [conn_fd]
		lea rsi, [request_data]
		mov rdx, 256
		mov rax, 0
		syscall

		mov qword ptr [request_size], rax

		mov eax, dword ptr [get_st]
		cmp dword ptr [request_data], eax
		je GET

		mov eax, dword ptr [post_st]
		cmp dword ptr [request_data], eax
		je POST
		jmp done
		
		GET:
			# extract the requested path from the request
			mov rdx, 100
			mov rcx, 0
			loop:
				cmp rcx, rdx
				je endloop
				cmp byte ptr [request_data+4+rcx], 0x20
				je endloop
				mov al, byte ptr [request_data+4+rcx]
				mov byte ptr [filename+rcx], al
				inc rcx
				jmp loop
			endloop:
			mov byte ptr [filename+rcx], 0

			# open the file requested
			lea rdi, [filename]
			mov rsi, 0
			mov rax, 2
			syscall

			mov word ptr [file_fd], ax # store the fd

			# read the file data
			mov rdi, qword ptr [file_fd]
			lea rsi, [file_data]
			mov rdx, 256
			mov rax, 0
			syscall

			# read the file data size
			mov rbx, rax
			
			# close the fd
			mov rax, 3
			syscall
			
			# send the header
			mov rdi, qword ptr [conn_fd]
			lea rsi, header
			mov rdx, 19
			mov rax, 1
			syscall
			
			# send the file data
			mov rdi, qword ptr [conn_fd]
			lea rsi, [file_data]
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
				cmp byte ptr [request_data+5+rcx], 0x20
				je endloop2
				mov al, byte ptr [request_data+5+rcx]
				mov byte ptr [filename+rcx], al
				inc rcx
				jmp loop2
			endloop2:
			mov byte ptr [filename+rcx], 0

			# find the offset for content to write
			mov rcx, 0
			loop3:
				cmp rcx, qword ptr [request_size]
				je endloop3
				cmp byte ptr [request_data+rcx], 0x0d
				jne next3
				cmp byte ptr [request_data+rcx+1], 0x0a
				jne next3
				cmp byte ptr [request_data+rcx+2], 0x0d
				jne next3
				cmp byte ptr [request_data+rcx+3], 0x0a
				jne next3
				add rcx, 4
				jmp endloop3
			next3:
				inc rcx
				jmp loop3
			endloop3:

			# store post data offset
			mov qword ptr [post_off], rcx

			# open the file requested
			lea rdi, [filename]
			mov rsi, 0x41  # set the O_WRONLY(0b1) | O_CREAT flag (0b1000000)
			mov rdx, 0x1ff # filemodee = 777 (rwx for all)
			mov rax, 2
			syscall
			
			mov word ptr [file_fd], ax # store the fd
			
			# load back post data offset
			mov rcx, qword ptr [post_off]
			# write to the fd
			mov rdi, [file_fd]
			lea rsi, [request_data+rcx]
			mov rax, qword ptr [request_size]
			sub rax, rcx
			mov rdx, rax
			mov rax, 1
			syscall

			# close the fd
			mov rdi, qword ptr [file_fd]
			mov rax, 3
			syscall
		
			# send ok response
			mov rdi, [conn_fd]
			lea rsi, header
			mov rdx, 19
			mov rax, 1
			syscall
		done:
			# close the conenction after sending the response or in the parent
			mov rdi, qword ptr [conn_fd]
			mov rax, 3
			syscall
		cmp byte ptr [isforked], 1
		je exit
		jmp mainloop
	# return the stack to previous point
	mov rsp, rbp
	pop rbp
exit:
	# exit the program
	mov rdi, 0
	mov rax, 60
	syscall
