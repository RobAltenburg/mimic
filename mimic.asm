 ; mimic - Mini Mailslot Internal Communicator
 ; Copyright (C) 2006  Robert Altenburg
 ; 
 ; This program is free software; you can redistribute it and/or
 ; modify it under the terms of the GNU General Public License
 ; as published by the Free Software Foundation; either version 2
 ; of the License, or (at your option) any later version.
 ; 
 ; This program is distributed in the hope that it will be useful,
 ; but WITHOUT ANY WARRANTY; without even the implied warranty of
 ; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ; GNU General Public License for more details.
 ; 
 ; You should have received a copy of the GNU General Public License
 ; along with this program; if not, write to the Free Software
 ; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, U

.386
.model flat,stdcall
option casemap:none
include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\kernel32.inc
include \masm32\include\comctl32.inc
include \masm32\include\masm32.inc
include \masm32\include\advapi32.inc
include \masm32\include\shell32.inc ;for the system tray

includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\comctl32.lib
includelib \masm32\lib\masm32.lib
includelib \masm32\lib\advapi32.lib
includelib \masm32\lib\shell32.lib

WinMain proto :DWORD,:DWORD,:DWORD,:DWORD
QueryProc proto :DWORD,:DWORD,:DWORD,:DWORD
BoxProc proto :DWORD,:DWORD,:DWORD,:DWORD
WriteMessage proto
WriteResults proto :DWORD
MyCreateMailslot proto
ErrorHandler proto 
SetControlPos proto :DWORD
StrLen proto :DWORD
TimerCallback proto :DWORD,:DWORD
XORBuffer proto :DWORD
GetRegString proto :DWORD,:DWORD,:DWORD,:DWORD
SetRegString proto :DWORD,:DWORD,:DWORD,:DWORD
RcptToPath proto

.const
DLI_HOST equ 2001
DLI_NICK equ 2002
IDM_EXIT equ 1001
IDM_QUERY equ 1002
IDM_CLEAR equ 1003
IDM_STEALTH equ 1004
IDM_ABOUT equ 1411
IDI_ICON equ 1014
IDI_ALERT equ 1015
ID_STATUSBAR equ 1004
ID_EDITINPUT equ 1005
ID_EDITOUTPUT equ 1006
ID_BTNSEND equ 1007
MAX_MSG_LEN equ 400 
MAX_SEND_BUFFER equ MAX_MSG_LEN + 23 ; msg + nick must be < 424
MAX_RESULTS_SIZE equ 0FFFh ; size of the results window
WM_SHELLNOTIFY equ WM_USER + 5

.data

buflen dd 16    ; this can't be an equ becaust the api wants a pointer to this value

ClassName db "MyWC",0
AppName  db "Mimic    ", 14 DUP (0) ;; alow space is for the system name
szEdit db "EDIT",0
szButton db "BUTTON",0
szSroll db "SCROLLBAR",0
DlgQueryName db "IDD_QUERY",0
DlgAboutName db "IDD_About",0
DlgName db "DlgboxProc",0
CRLF db 0Dh, 0Ah, 0
stealthMode db FALSE
szKeyName db "Software\Mimic\", 0
szValueHost db "Hostname", 0
szValueNick db "Nick", 0
MenuName db "MailslotMenu",0
szSlotName db "\\.\mailslot\mimic",0
; !!! These next two lines must remain adjacent in memory !!!
    sStatusHeader db "Recipient: " ; not null terminated
    szSlotNameClient db "\\.\mailslot\mimic", 0EDh DUP(0)
; -----------------------------------------------------------
szMessageBuffer db MAX_SEND_BUFFER  DUP (0)
szLastMsgBuffer db MAX_SEND_BUFFER DUP (0)
szRcptName db ".", 03Eh  DUP (0)
szNickName db "?", 12 DUP (0)
szNickTail db ": ", 0 ; the prompt after the nick
szSend db "Send", 0
szNull db 0
szPing db "/ping", 0

.data?
hInstance HINSTANCE ?
hTimer DWORD ?
hHeap DWORD ?
szResults DWORD ?
pResults DWORD ?
hSlot DWORD ?
hFile1 DWORD ?
nBytesWritten DWORD ?
nBytesRead DWORD ?
nMessageCount DWORD ?
nNextSize DWORD ?
nBytesToWrite DWORD ?

;registry
phkResult DWORD ?
lpdwDisposition DWORD ?
lpType DWORD ?

CommandLine LPSTR ?
hEditControl HWND ?
hEditOutCtrl HWND ?
hBtnSendControl HWND ?
hStatusBar HWND ?
hWndMain HWND ?
hMenu HMENU ?

stMenuInfo MENUITEMINFO <?>

;system tray stuff
NotifyID NOTIFYICONDATA <?>

 ; Things to add:
 ; Reciept confirmation
 ; Make a more generic message passing format

; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
;                                                              MACROS
; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
StrCpy MACRO dest:REQ, source:REQ

    mov esi, source
    mov edi, dest
    cld
 @@:
    lodsb
    stosb
    cmp al, 0
    jne @B

ENDM

; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
;                                                              START
; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
.code

start:
    invoke GetModuleHandle, NULL
    mov  hInstance,eax

    ;; open a mailslot on the local machine
    invoke MyCreateMailslot

    ;; set the computer name
    invoke GetComputerName, ADDR AppName + 7  , OFFSET buflen

    ;; allocate memory for the scroll window
    invoke HeapCreate, HEAP_GENERATE_EXCEPTIONS, MAX_RESULTS_SIZE, 0
    mov hHeap, eax
    invoke HeapAlloc, hHeap, HEAP_GENERATE_EXCEPTIONS or HEAP_ZERO_MEMORY,\
	MAX_RESULTS_SIZE
    mov szResults, eax
    mov pResults, eax ; set a pointer to the start of the heap

    ;; Get the last server from the registry
   invoke GetRegString, OFFSET szRcptName,
                        HKEY_CURRENT_USER,
                        OFFSET szKeyName,
                        OFFSET szValueHost
                        
   invoke RcptToPath ;change the name to the receive path
                
   ;; Get the Nick Name
   invoke GetRegString, OFFSET szNickName,
                        HKEY_CURRENT_USER,
                        OFFSET szKeyName,
                        OFFSET szValueNick

    invoke GetCommandLine
    mov CommandLine,eax
    invoke	InitCommonControls    
    invoke WinMain, hInstance,NULL,CommandLine, SW_SHOWDEFAULT
    invoke ExitProcess,eax    

; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
;                                                               WinMain
; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
WinMain proc hInst:HINSTANCE,hPrevInst:HINSTANCE,CmdLine:LPSTR,CmdShow:DWORD
	LOCAL wc:WNDCLASSEX
	LOCAL msg:MSG
	LOCAL hwnd:HWND
	LOCAL hTimerQueue: DWORD
	mov   wc.cbSize,SIZEOF WNDCLASSEX
	mov   wc.style, CS_HREDRAW or CS_VREDRAW
	mov   wc.lpfnWndProc, OFFSET WndProc
	mov   wc.cbClsExtra,NULL
	mov   wc.cbWndExtra,NULL
	push  hInstance
	pop   wc.hInstance
	mov   wc.hbrBackground,COLOR_WINDOW+1
	mov   wc.lpszMenuName,OFFSET MenuName
	mov   wc.lpszClassName,OFFSET ClassName
	invoke LoadIcon,hInst,IDI_ICON
	mov   wc.hIcon,eax
	mov   wc.hIconSm,eax
	invoke LoadCursor,NULL,IDC_ARROW
	mov   wc.hCursor,eax
	invoke RegisterClassEx, addr wc
	INVOKE CreateWindowEx,NULL,ADDR ClassName,ADDR AppName,\
           WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,\
           CW_USEDEFAULT,500,300,NULL,NULL,\
           hInst,NULL
	mov   hwnd,eax
      invoke ShowWindow, hwnd,SW_SHOWNORMAL
	invoke UpdateWindow, hwnd
        
      invoke GetMenu, hwnd
      mov hMenu, eax

  ;; create timer
    invoke CreateTimerQueue
    mov hTimerQueue, eax
    invoke CreateTimerQueueTimer, OFFSET hTimer, hTimerQueue, OFFSET TimerCallback,\
	hwnd, 2500, TRUE, NULL

  ;; Set the system tray icon
  ;; note: icon may change if messages are received while in stealth mode
    mov NotifyID.cbSize, sizeof NOTIFYICONDATA
    push hwnd
    pop NotifyID.hwnd
    mov NotifyID.uID, IDI_ICON  
    mov NotifyID.uFlags,NIF_ICON+NIF_MESSAGE+NIF_TIP
    mov NotifyID.uCallbackMessage,WM_SHELLNOTIFY
    push wc.hIcon
    pop NotifyID.hIcon
    ;todo: add the tool tip
    ;mov eax, OFFSET AppName
    ;mov NotifyID.szTip, eax
    invoke Shell_NotifyIcon, NIM_ADD, OFFSET NotifyID     

  ;; Message loop  
	.WHILE TRUE
		invoke GetMessage, ADDR msg, NULL, 0, 0
		.BREAK .IF (!eax)
            ;; Catch the enter key to send the message        
            .if msg.message == WM_KEYDOWN
                .if msg.wParam == VK_RETURN
                  mov ax, 405 ;set max message size
                  mov edi, OFFSET szMessageBuffer
                  mov [edi], ax

                  invoke SendMessage, hEditControl, EM_GETLINE, NULL, OFFSET szMessageBuffer
                  invoke SendMessage, hEditControl, WM_SETTEXT, NULL, OFFSET szNull                
                  invoke WriteResults, FALSE
                  invoke WriteMessage
                  
                 .elseif msg.wParam == VK_UP
                  invoke SendMessage, hEditControl, WM_SETTEXT, NULL, OFFSET szLastMsgBuffer             
                .endif
            .endif
            ;; ------ end catch -------
		invoke TranslateMessage, ADDR msg
		invoke DispatchMessage, ADDR msg
	.ENDW
	mov     eax,msg.wParam
	ret
WinMain endp

; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
;                                                           Event Loop
; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл

WndProc proc hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
	.IF uMsg==WM_DESTROY
		invoke Shell_NotifyIcon, NIM_DELETE, OFFSET NotifyID     
            invoke CloseHandle, hFile1
            invoke HeapDestroy, hHeap
		invoke PostQuitMessage,NULL

; -------------------------------------------------------------------------
	.ELSEIF uMsg==WM_CREATE
            invoke GetDesktopWindow
            
            ;Create the Edit window
            mov eax, WS_CHILD or WS_BORDER or WS_VISIBLE or ES_AUTOHSCROLL
            invoke CreateWindowEx, WS_EX_CLIENTEDGE, ADDR szEdit, NULL, eax, \
            0, 0, 0, 0, \
            hWnd, ID_EDITINPUT, hInstance, NULL
            mov hEditControl, eax
            invoke SendMessage, hEditControl, EM_LIMITTEXT, MAX_MSG_LEN, NULL
            invoke SetForegroundWindow,  hEditControl

            ;The Output Window
            mov eax, WS_CHILD or WS_BORDER or WS_VISIBLE or ES_MULTILINE or \
	    ES_AUTOVSCROLL or WS_VSCROLL 
            invoke CreateWindowEx, WS_EX_CLIENTEDGE , ADDR szEdit, NULL, eax, \
            0, 0, 0, 0, \
            hWnd, ID_EDITOUTPUT, hInstance, NULL
            mov hEditOutCtrl, eax
            invoke SendMessage, hEditOutCtrl, EM_SETREADONLY, TRUE, NULL

	    ;Create the Status Window
  	    invoke CreateStatusWindow, WS_CHILD + WS_BORDER + WS_VISIBLE, \
            ADDR sStatusHeader, hWnd, ID_STATUSBAR
            mov	hStatusBar,eax         

; -------------------------------------------------------------------------
	.ELSEIF uMsg==WM_SIZE
        .if wParam == SIZE_MINIMIZED
          invoke ShowWindow,hWnd,SW_HIDE 
        .else
	     invoke	SendMessage, hStatusBar, uMsg, wParam, lParam
           invoke SetControlPos, hWnd
        .endif
; -------------------------------------------------------------------------
	.ELSEIF uMsg==WM_COMMAND
		mov eax, wParam
            ;-----------------------------------------------  Menu About
		.if ax==IDM_ABOUT
			invoke CreateDialogParam,hInstance, addr DlgAboutName,hWnd,\
			OFFSET BoxProc,NULL
                    .if eax==NULL
					invoke ErrorHandler
                    .endif
            ;-----------------------------------------------  Menu Set Recipient
		.elseif ax==IDM_QUERY
			invoke CreateDialogParam,hInstance, addr DlgQueryName,hWnd,\
			OFFSET QueryProc,NULL
                    .if eax==NULL
					invoke ErrorHandler
                    .endif             
            ;-----------------------------------------------  Menu Set Stealth Mode
		.elseif ax==IDM_STEALTH
                mov stMenuInfo.cbSize, SIZEOF WNDCLASSEX
                invoke GetMenuItemInfo, hMenu, IDM_STEALTH, FALSE, OFFSET stMenuInfo
                .if eax != 0
                    mov stMenuInfo.fMask, MIIM_STATE
                    .if stMenuInfo.fState == MFS_CHECKED
                        mov stMenuInfo.fState, MFS_UNCHECKED
                        invoke SetMenuItemInfo, hMenu, IDM_STEALTH, FALSE,\
			OFFSET stMenuInfo
                        mov stealthMode, FALSE
                    .else
                        mov stMenuInfo.fState, MFS_CHECKED
                        invoke SetMenuItemInfo, hMenu, IDM_STEALTH, FALSE,\
			OFFSET stMenuInfo
                        mov stealthMode, TRUE                        
                    .endif
                .else
                    invoke ErrorHandler
                .endif
            ;-----------------------------------------------  Clear Screen	
		.elseif ax==IDM_CLEAR
			invoke ClearScreen       
          ;-----------------------------------------------  Menu Exit  	
		.elseif ax==IDM_EXIT
			invoke DestroyWindow, hWnd  
		.endif
; -------------------------------------------------------------------------
	.ELSEIF uMsg==WM_SHELLNOTIFY
       .if wParam==IDI_ICON
            .if lParam==WM_LBUTTONDBLCLK
                   invoke ShowWindow,hWnd,SW_RESTORE 
             .endif
       .elseif wParam==IDI_ALERT
            .if lParam==WM_LBUTTONDBLCLK
                   invoke ShowWindow,hWnd,SW_RESTORE
                   invoke Shell_NotifyIcon, NIM_DELETE, OFFSET NotifyID
                   invoke LoadIcon,hInstance,IDI_ICON
                   mov NotifyID.hIcon, eax                                
	             mov NotifyID.uID, IDI_ICON
                   invoke Shell_NotifyIcon, NIM_ADD, OFFSET NotifyID 
             .endif
       .endif
      .ELSE
        ;
	.ENDIF
        	invoke DefWindowProc,hWnd,uMsg,wParam,lParam		
		ret
WndProc endp

; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл
;                                                              Procedures
; ллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллллл

; -------------------------------------------------------------------------
; Alert Beep
; -------------------------------------------------------------------------
AlertBeep proc
	
	invoke Beep, 1400, 33
	invoke Beep, 2800, 33
	invoke Beep, 1400, 33

	xor eax, eax
	ret

AlertBeep endp

; -------------------------------------------------------------------------
; Clear Screen
; -------------------------------------------------------------------------
ClearScreen proc

  mov edi, [szResults]
  mov [pResults], edi
  mov ecx, 2
  mov ax, 0
  cld
  rep stosw

    invoke SendMessage, hEditOutCtrl, WM_SETTEXT, NULL, szResults
    
  xor eax, eax
  ret

ClearScreen endp

; -------------------------------------------------------------------------
; Write to Results Buffer
; -------------------------------------------------------------------------
WriteResults proc bExternal:DWORD
    .data
        myHeader db "> ", 0
    .code 

    ; if this is not an external message, print the header
    ; (this lets you see what you typed in the results window)
    .if bExternal == FALSE
        StrCpy pResults, OFFSET myHeader
        dec edi
        mov pResults, edi 
    .endif

    ;Have we used most of the buffer?
    mov eax, [pResults]
    sub eax, [szResults]
    add eax, MAX_SEND_BUFFER
    sub eax, 2 ;allow space for the header

    .if eax >= MAX_RESULTS_SIZE
    ; --------------------------------- Scroll the Memory Buffer --------------
        xor ecx, ecx 
        .while (ecx < [nBytesRead])
          mov eax, [szResults]
          mov ebx, [eax]
          xor ecx, ecx
          .while (bx != 0ah) ; look for a LF to break on 
            inc eax
            mov ebx, [eax]
            inc ecx
          .endw
            inc ecx
        .endw
            inc eax
            mov esi, eax ; esi is the source of the new string

        ; move the tail pointer
        mov eax, [pResults]
        sub eax, ecx ;
        mov [pResults],eax

        ; calc how much to copy
        mov eax, ecx
        mov ecx, MAX_RESULTS_SIZE
        sub ecx, eax 
        
        ; move the block down in memory
        cld
        mov edi, [szResults]
        rep movsb
    ; -------------------------------------------------------------------------
    .endif

    StrCpy pResults, OFFSET szMessageBuffer
    dec edi
    mov pResults, edi 

    StrCpy pResults, OFFSET CRLF
    dec edi
    mov pResults, edi 
   
    invoke SendMessage, hEditOutCtrl, WM_SETTEXT, NULL, szResults
    @@:
    
    ;scroll the message box if necessary
    mov eax, [pResults]
    sub eax, [szResults]
    invoke SendMessage, hEditOutCtrl, EM_LINEFROMCHAR, eax, NULL
    invoke SendMessage, hEditOutCtrl, EM_LINESCROLL, 0, eax

    xor eax, eax
    ret
    
WriteResults endp
; -------------------------------------------------------------------------
; Create Mailslot
; -------------------------------------------------------------------------
MyCreateMailslot proc
invoke CreateMailslot, ADDR szSlotName, NULL,0, NULL
    .if eax == INVALID_HANDLE_VALUE
        invoke ErrorHandler
    .else
        mov hSlot, eax
    .endif
    mov eax, TRUE
    ret
MyCreateMailslot endp

; -------------------------------------------------------------------------
; Write Mailslot
; -------------------------------------------------------------------------
WriteMessage proc
    invoke szCmp, OFFSET szMessageBuffer,  OFFSET szPing
    .if eax == 0 ; no match
    
        ;Add nick to the front of the string
        StrCpy OFFSET szLastMsgBuffer, OFFSET szMessageBuffer
        invoke szCopy ,OFFSET szNickName, OFFSET szMessageBuffer  
        invoke szCatStr, OFFSET szMessageBuffer, OFFSET szNickTail      
        invoke szCatStr, OFFSET szMessageBuffer, OFFSET szLastMsgBuffer

    .endif

    invoke XORBuffer, OFFSET szMessageBuffer

    invoke CreateFile, OFFSET szSlotNameClient,GENERIC_WRITE,FILE_SHARE_READ,\
      NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
        .if eax==INVALID_HANDLE_VALUE
            invoke ErrorHandler
            mov eax, FALSE
            ret
        .else
 
            ; file is open, so write
            mov hFile1, eax	
    		invoke lstrlen, OFFSET szMessageBuffer
    		mov nBytesToWrite, eax
    		inc nBytesToWrite
    		invoke WriteFile, hFile1, OFFSET szMessageBuffer,\
    			 nBytesToWrite, OFFSET nBytesWritten, NULL
    		.if eax==NULL
    			invoke ErrorHandler
    		.else
    		.endif
    
            ; close the file
            invoke CloseHandle, hFile1
            .if eax==NULL
                invoke ErrorHandler
            .endif
            
        .endif

    mov eax, TRUE
    ret

WriteMessage endp

; -------------------------------------------------------------------------
; Generic dialog box callback function.  All it does is close the box
; -------------------------------------------------------------------------
BoxProc proc EXPORT hDlg:HWND,iMsg:DWORD,wParam:WPARAM, lParam:LPARAM
        .if iMsg==WM_INITDIALOG
        .elseif iMsg==WM_COMMAND
		mov eax,wParam
		.if ax==IDOK
			invoke EndDialog, hDlg, 0
            .elseif ax==IDM_EXIT
			invoke EndDialog, hDlg, 0            
		.endif	   
        .else
		mov eax,FALSE
		ret
        .endif
        mov  eax,TRUE
        ret
BoxProc endp

; -------------------------------------------------------------------------
; RcptToPath: convert system name to network path
;   [in] szRcptName
;   [out] szSlotNameClient
; -------------------------------------------------------------------------
RcptToPath proc
    .data
        szPrefix db "\\",0
        szEnding db "\mailslot\mimic",0
    .code

                  ;empty the buffer
                  mov edi, OFFSET szSlotNameClient
                  mov ecx, 0EDh
                  mov ax, 0
                  cld
                  rep stosw	

                  ; add the prefix
                  mov edi, OFFSET szSlotNameClient
                  mov esi, OFFSET szPrefix
                  mov ecx, 2
                  rep movsb

                  mov esi, OFFSET szRcptName
                  cld
               @@:
                  lodsb
                  stosb
                  cmp al, 0
                  jne @B

                  dec edi
                  
                  ; add the suffix
                  mov esi, OFFSET szEnding
                  mov ecx, 16
                  rep movsb

    xor eax, eax
    ret
RcptToPath endp

; -------------------------------------------------------------------------
; dialog box callback to set the target system name
; -------------------------------------------------------------------------
QueryProc proc EXPORT hDlg:HWND,iMsg:DWORD,wParam:WPARAM, lParam:LPARAM

        .if iMsg==WM_INITDIALOG
           	invoke SetDlgItemText, hDlg, DLI_NICK, OFFSET szNickName
           	invoke SetDlgItemText, hDlg, DLI_HOST, OFFSET szRcptName           
        .elseif iMsg==WM_COMMAND
		mov eax,wParam
		.if ax==IDOK

                invoke GetDlgItemText, hDlg, DLI_HOST, OFFSET szRcptName, 03Fh 
                invoke GetDlgItemText, hDlg, DLI_NICK, OFFSET szNickName, 0Fh 

                invoke RcptToPath
                invoke SetRegString,  HKEY_CURRENT_USER, OFFSET szKeyName,\
			OFFSET szValueHost,OFFSET szRcptName
                invoke SetRegString,  HKEY_CURRENT_USER, OFFSET szKeyName,\
			OFFSET szValueNick,OFFSET szNickName
                invoke SendMessage, hStatusBar, WM_SETTEXT, NULL, OFFSET sStatusHeader

            invoke EndDialog, hDlg, 0
            .elseif ax==IDM_EXIT
                  invoke EndDialog, hDlg, 0
		.endif	   
        .else
		mov eax,FALSE
		ret
        .endif
        mov  eax,TRUE
        ret
QueryProc endp

; -------------------------------------------------------------------------
; Error Handler
; -------------------------------------------------------------------------
ErrorHandler proc
    .data
        msgBuffer db 530 DUP (0)
    .data?
        nLastError DWORD ?
    .code    
    invoke GetLastError
    mov nLastError, eax
    invoke FormatMessage,\
	FORMAT_MESSAGE_FROM_SYSTEM,\
	NULL, nLastError, NULL, ADDR msgBuffer, 530, NULL
    invoke MessageBoxEx, NULL, ADDR msgBuffer, NULL,MB_OK+MB_ICONINFORMATION,\
	LANG_ENGLISH
    mov  eax,TRUE
    ret
ErrorHandler endp

; -------------------------------------------------------------------------
; Locate the controls on the window
; -------------------------------------------------------------------------
SetControlPos  proc EXPORT, hParent:HWND
    Local rcP:RECT, rcC:RECT, yNew:DWORD, xWidth:DWORD,  xWidMinus2:DWORD
            
    invoke GetWindowRect, hParent, ADDR rcP
    .if (eax)
        ;get width
        mov eax, rcP.right
        sub eax, rcP.left
        sub eax, 8
        mov xWidth, eax

        sub eax, 2
        mov xWidMinus2, eax
        
        ;get height
        mov eax, rcP.bottom
        sub eax, rcP.top
        sub eax, 90
        mov yNew, eax

    invoke SetWindowPos, hEditOutCtrl, NULL, 0, 0, xWidth, yNew, SWP_SHOWWINDOW 
    invoke SetWindowPos, hEditControl, NULL, 0, yNew, xWidMinus2, 25, SWP_SHOWWINDOW   
    .endif
    
    mov eax, TRUE
    ret
SetControlPos endp

; -------------------------------------------------------------------------
; Timer Queue Callback
; -------------------------------------------------------------------------
TimerCallback proc lpParam:DWORD, TimerFired:DWORD
    .data
        szAlive db "pong: ", 0
    .code
        invoke GetMailslotInfo, hSlot, NULL, OFFSET nNextSize,\
		OFFSET nMessageCount, NULL
        .if eax==NULL
		;; no message, do nothing
        .elseif nNextSize == MAILSLOT_NO_MESSAGE
		;; no message, do nothing
	  .else
            .while nMessageCount > 0  ;; loop through the messages
		  invoke ReadFile, hSlot, OFFSET szMessageBuffer,\
			nNextSize, OFFSET nBytesRead, NULL
		  .if eax==NULL
		      invoke ErrorHandler
		  .else
                invoke XORBuffer, OFFSET szMessageBuffer  
                invoke szCmp, ADDR szMessageBuffer,  ADDR szPing
                .if eax != 0
                      ; received a ping message
                      StrCpy OFFSET szMessageBuffer, OFFSET szAlive
		      invoke szCatStr, OFFSET szMessageBuffer, ADDR AppName + 7
                      invoke WriteMessage
                .else
                      ; recieve a non-ping message
                       invoke IsIconic, lpParam
                       .if eax!=0 
                            .if stealthMode == TRUE
                                ; If it's minimized and stealthed, change the systray icon
                                invoke Shell_NotifyIcon, NIM_DELETE, OFFSET NotifyID
                                invoke LoadIcon,hInstance,IDI_ALERT
                                mov NotifyID.hIcon, eax                                
	                        mov NotifyID.uID, IDI_ALERT
                                invoke Shell_NotifyIcon, NIM_ADD, OFFSET NotifyID
                            .else
                                ; if it's minimized but not stealthed, pop it up 
			    invoke SetForegroundWindow, lpParam
                            invoke ShowWindow, lpParam, SW_RESTORE	
			    invoke AlertBeep
                                ;invoke OpenIcon, lpParam
                                ;invoke SetWindowPos, lpParam, HWND_TOP, 0, 0, 0, 0,\
				;	SWP_NOMOVE or SWP_NOSIZE
                            .endif
                        .else
                            ;if it's not minimized, pop it up
			    invoke SetForegroundWindow, lpParam
                            invoke ShowWindow, lpParam, SW_SHOW		    
			    ;invoke SetWindowPos, lpParam, HWND_TOP, 0, 0, 0, 0,\
			    ; SWP_NOMOVE or SWP_NOSIZE or SWP_SHOWWINDOW
                        .endif
                        ;
                           
                      invoke WriteResults, TRUE
                .endif
		  .endif
                ; next two
              invoke GetMailslotInfo, hSlot, NULL, OFFSET nNextSize, OFFSET nMessageCount, NULL	
	      .endw
	   .endif


    xor eax, eax
    ret
TimerCallback endp

; -------------------------------------------------------------------------
; Buffer XOR
; XOR each byte of an asciiz string with a given value
; this obfuscates the transmission to give more privacy
; -------------------------------------------------------------------------
XORBuffer proc lpBuffer:DWORD
    mov esi, lpBuffer
    mov bl, 0A5h ; don't use a value that is an ascii text value
    mov al, BYTE PTR [esi]
    .while al != 0
        xor al, bl
        mov BYTE PTR [esi], al
        inc esi
        mov al, BYTE PTR [esi]
    .endw   
        xor eax, eax
        ret
XORBuffer endp

; -------------------------------------------------------------------------
; Registry Access
; -------------------------------------------------------------------------
SetRegString  proc MyHKEY: dword, lpszKeyName: dword, lpszValueHost: dword, lpszString: dword
    local Disp: dword
    local pKey: dword
    local dwSize: dword
    invoke RegCreateKeyEx, MyHKEY, lpszKeyName, NULL, NULL, REG_OPTION_NON_VOLATILE,
        KEY_ALL_ACCESS, NULL, addr pKey, addr Disp
    .if eax == ERROR_SUCCESS
        invoke lstrlen, lpszString
        mov dwSize, eax
        invoke RegSetValueEx, pKey, lpszValueHost,
            NULL, REG_SZ,
            lpszString, dwSize
        push eax
        invoke RegCloseKey, pKey
        pop eax
    .else
        invoke ErrorHandler    
    .endif
    ret
SetRegString endp 


GetRegString proc lpszBuffer: dword, MyHKEY: dword, lpszKeyName: dword, lpszValueHost: dword
    local TType: dword
    local pKey: dword
    local dwSize: dword
    mov TType, REG_SZ
    invoke RegCreateKeyEx, MyHKEY, lpszKeyName, NULL, NULL, REG_OPTION_NON_VOLATILE,
        KEY_ALL_ACCESS, NULL, addr pKey, addr TType
    .if eax == ERROR_SUCCESS
        mov eax, REG_DWORD
        mov TType, eax
        inc dwSize
        invoke RegQueryValueEx, pKey, lpszValueHost,
            NULL, addr TType,
            lpszBuffer, addr dwSize
        push eax
        invoke RegCloseKey, pKey
        pop eax
        ret
    .endif
    mov eax, FALSE
    ret
GetRegString endp

; ------------------------------------------------------------------------- 

end start
