ROOT = c:\masm32

ASM = $(ROOT)\bin\ml
CFLAGS = /c /coff /Zi /Cp
RC = $(ROOT)\bin\rc
LINK = $(ROOT)\bin\link
DEBUG = /DEBUG /DEBUGTYPE:CV
LFLAGS = /SUBSYSTEM:WINDOWS /LIBPATH:$(ROOT)\lib

mimic.exe: mimic.obj mimic.res
	$(LINK) $(LFLAGS) mimic.obj mimic.res

mimic.obj: mimic.asm
	$(ASM) $(CFLAGS) mimic.asm

mimic.res: mimic.rc mimic.ico mimicalert.ico 
	$(RC) mimic.rc
	
clean:
	rm mimic.exe mimic.obj mimic.res
