import simpleUDP
import strutils, os

proc testSender() = 
    
    var mymsg: cstring
    var mychr : array[50,char]

    echo "Enter the Servers IP."
    var ipOfServer = readline(stdin)
    if  ipOfServer == "" :
        ipOfServer = "127.0.0.1"

    echo "Enter the Servers Port Number."
    var myport = readline(stdin)
    if  myport == "" :
         myport = "12346"
    
    var mySender = addPeer(ipOfServer,myport.parseInt)

    echo "Start typing your Messages."

    while mymsg != "exit" :
        echo "--->"
        mymsg = readLine(stdin)
        
        sendData(mySender,cstring(mymsg), mymsg.len)

        if mymsg == "+++" :
            for ii in 0..300 :
                
                mymsg  = "FLOOD"
                
                sendData(mySender,cstring(mymsg), mymsg.len)
                
    

proc testListener() =
    

    var c : array[5,char]
    var mylistener : array[29,int]


    for ii in 0..<29 :
        
        mylistener[ii] = addListenPort(ii+12346,5)
        echo "Started Listener ",mylistener[ii]," ii= ",ii

    var tRunning : bool = true
    while tRunning :
        
        sleep(10) # just to keep mainloop from hogging all cpu cycles
        for ii2 in 0..<29 :
            var tmp = recvData(mylistener[ii2],addr c)            
            if tmp > 0 :
                
                echo "From Listener ",ii2," ---> ",c
                if c[0] == '.' :
                    tRunning = false

    echo "Stop Listeners"                
    for iii in 0..<29 :
        delListenPort(mylistener[iii]) 
        


discard initUpd(5) #

echo "Type 'L' for Listener test example or 'S' for Sender Example"
var tmp = readLine(stdin)
if tmp == "L" or tmp == "l" :
    testListener()
else :
    testSender()
    


deinitUpd()
#
