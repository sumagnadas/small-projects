.intel_syntax noprefix
.data
	header: 
		.asciz "HTTP/1.0 200 OK\r\n\r\n"
	get_st:  .ascii "GET "
	post_st:  .asciz "POST"
.bss
	filename: .space 100
	request_data: .space 256
	file_data: .space 256
	socket_fd: .space 8
	conn_fd: .space 8
	file_fd: .space 8
.text
.global _start

exit:
	mov rax, 60
	syscall
	ret # just for the sake of it
socket:
	mov rax, 41
	syscall
	ret

bind:
	mov rax, 49
	syscall
	ret
listen:
	mov rax, 50
	syscall
	ret
accept:
	mov rax, 43
	syscall
	ret
open:
	mov rax, 2
	syscall
	ret
write:
	mov rax, 1
	syscall
	ret
close:
	mov rax, 3
	syscall
	ret
read:
	mov rax, 0
	syscall
	ret
_start:
	# create a socket
	mov rdi, 2
	mov rsi, 1
	mov rdx, 0
	call socket

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
	call bind

	# listen on the bound port
	mov rdi, qword ptr [socket_fd]
	mov rsi, 0
	call listen

	# accept incoming connections
	mov rdi, qword ptr [socket_fd]
	mov rsi, 0
	mov rdx, 0
	call accept

	# store the fd for the connection
	mov word ptr [conn_fd], ax

	# read the request
	mov rdi, qword ptr [conn_fd]
	lea rsi, [request_data]
	mov rdx, 256
	call read

	mov eax, dword ptr [get_st] 
	cmp dword ptr [request_data], eax
	je GET

	mov eax, dword ptr [post_st]
	cmp dword ptr [request_data], eax
	je POST
	jmp done
	
	GET:
		# extract the filename from the request
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
		call open

		mov word ptr [file_fd], ax # store the fd

		# read the file data
		mov rdi, qword ptr [file_fd]
		lea rsi, [file_data]
		mov rdx, 256
		call read

		# read the file data size
		mov rbx, rax
		call close
		
		# send the header
		mov rdi, qword ptr [conn_fd]
		lea rsi, header 
		mov rdx, 19
		call write
		
		# send the file data
		mov rdi, qword ptr [conn_fd]
		lea rsi, [file_data]
		mov rdx, rbx
		call write

		jmp done
	POST:
		mov rdi, rbx
		lea rsi, header 
		mov rdx, 19
		call write

	done:
	# close the conenction after sending the response
		mov rdi, 0
		mov di, word ptr [conn_fd]
		call close

	# return the stack to previous point
	mov rsp, rbp
	pop rbp

	# exit the program
	mov rdi, 0
	call exit
