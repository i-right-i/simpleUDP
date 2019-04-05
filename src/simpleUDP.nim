#------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2019 - Ben Olmstead
#
# All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#------------------------------------------------------------------------------

# --------------- Todo --------------------------------
# Add Proc to check if port is available to open. 
# Add error checking for open ports.
# Add Error codes/Proc

# ------------- Imports -- Includes -------------------
import net, locks, os
#-------------------- Constants -----------------------
const LocalIp* = "127.0.0.1"
#const ReadTimeOut = 5  # can make mutable later
const NewThreadTimeOut = 5
const AfterSpawnTimeOut =1
const MaxPort* =65535
const MinPort* = 1
const MaxPeers = 30  # Safe to change this value
const MaxListen = 30 # Safe to change this value
const PacketSizeMax* = 512
const PacketSizeMin* = 1

#const On = 1 # For simple toggleIt Function
#const Off = 0


#-------------------- Types / Objects -----------------
type
    ListenObj = object
        port : int
        readSize : int
        dataLock : Lock
        
        data : pointer      # dataLock on this data. Its the Only data that gets written to between Init and DeInit
        needRead : bool
        run : bool
        dataSize : int
        thread: Thread[ptr ListenObj]
        


    PeerObj = object
        ip : string
        port : int
    

    


#-------------------- Declarations --------------------
#-----Public--

#-----Private--
#proc toggleIt(i:int) : int = result = On - i    Not used
proc listenThread(listener:ptr ListenObj){.thread.}
proc sendEmpty(port:int,size:int)
proc portIsOpen(port: int ): bool #returns true if port is in use and false if not.
#-------------------- Globals -------------------------
var readWaitTime: int = 5
var InitRan : bool = false
#var peerList : array[MaxPeers,PeerObj] 
#var peerIdIndex : int = 0
var peerIdCount : int = 0
var peerListLock: Lock
var peerList : ptr array[MaxPeers,PeerObj] # Shared Memory
var peerSocket : Socket

var listenerListCount : int = 0
var listenerListLock : Lock
var listenerList : ptr array[MaxListen,ListenObj] # Shared Memory


#------------------- Interface Functions---------------

proc initUpd*(readTimeOut: int = 5) : int {.discardable.} = # 
    
    if readTimeOut < 1 :
        readWaitTime = 1
    else:
            readWaitTime = readTimeOut
    
    
    result = 1
    initLock(peerListLock)
        
    acquire(peerListLock)
    peerList = cast[ptr array[MaxPeers,PeerObj]](allocShared0(sizeof(PeerObj)*MaxPeers))
    if peerList == nil :
        release(peerListLock)
        return -1 
    
    peerSocket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP,false)       
    release(peerListLock)

    initLock(listenerListLock)
        
    acquire(listenerListLock)
    listenerList = cast[ptr array[MaxListen,ListenObj]](allocShared0(sizeof(ListenObj)*MaxListen))
    if listenerList == nil :
        result = -2
    release(listenerListLock)

proc deinitUpd*() =
    acquire(peerListLock)
    close(peerSocket)
    deallocShared(peerList)
    release(peerListLock)
    deinitLock(peerListLock) 

    acquire(listenerListLock)
    deallocShared(listenerList)
    release(listenerListLock)
    deinitLock(listenerListLock)
    InitRan = false


proc addPeer*(ip: string,port: int) : int =  # returns Id of peer added to send the data to, -1 if error
    # Add ip string checks for bad ip.
    if ip == "" or port < MinPort or port > MaxPort :
        return -1
    var firstEmptyNotFound : bool = true
    var firstEmptyId : int

    acquire(peerListLock)  # Acquire Lock for peerlist. 
    for i in 0..<MaxPeers :  # Iterate through array, First look for duplicate port/id and look for first empty
        
        if peerList[i].ip == ip and peerList[i].port == port :  # Check if duplicate.
            release(peerListLock)
            return i #return id of duplicate port/ip
        
        if peerList[i].ip == "" and firstEmptyNotFound: #True If array is empty. And this is the first empty place found.
            firstEmptyId = i # save index in the array were the first empty place was found.
            firstEmptyNotFound = false # Yes an empty place was found so set firstEmptyNotFound to false.
    
    
    if firstEmptyNotFound : # If we get to this point wihtout finding an empty place or duplicate, must mean array is full.
        release(peerListLock)
        return -1 #Error Reached Max number of peers.
    
    else: # Empty place in the array was found, but no duplicate or function would have returned
        peerList[firstEmptyId].ip = ip # Store Empty with new IP/Port
        peerList[firstEmptyId].port = port
        release(peerListLock)
        return firstEmptyId
        
           
proc delPeer*(id: int) =
    if id < 0 or id > (MaxPeers-1) :  #<------- Error reported here
        return
    #echo "id=",id
    acquire(peerListLock)
    peerList[id].ip = ""
    peerList[id].port = 0
    release(peerListLock)

proc sendData*(id: int ,data: pointer,size :int) =  # Doesn't need to be in threaded
    #
    if id < 0 or id > (MaxPeers-1) :
        return
    acquire(peerListLock)
    if peerList[id].port == 0 :
        release(peerListLock)
        return
    if size < PacketSizeMin or size > PacketSizeMax :
        release(peerListLock)
        return
    if data == nil :
        release(peerListLock)
        return
    
    peerSocket.sendTo(peerList[id].ip, Port(peerList[id].port), data,size)
    release(peerListLock)



proc addListenPort*(port: int,readSize:int) : int = # Returns Id of Listener. Thread for each Listener / Lock and Shared Data Buffer for each.
    
    if port < MinPort or port > MaxPort : #checks weather port is within range.
        return -1
    
    if port.portIsOpen() : #check if port is open here
        #error code here
        return -2

    var ireadSize : int = readSize

    if ireadSize < PacketSizeMin :
        ireadSize = PacketSizeMin
    if ireadSize > PacketSizeMax :
        ireadSize = PacketSizeMax
    

    acquire(listenerListLock)
    if listenerListCount >= Maxlisten : # error when max listener limit reached.
        return -1

    for i in 0..<MaxListen :
        if listenerList[i].port == 0 :
            initLock(listenerList[i].dataLock)
            acquire(listenerList[i].dataLock)
            listenerList[i].readSize = ireadSize
            listenerList[i].port = port
            listenerList[i].run = true
            listenerList[i].needRead = false
                        
            createThread[ptr ListenObj](listenerList[i].thread,listenThread, addr listenerList[i])
            
            sleep (AfterSpawnTimeOut)   # For debug puposes mainly.
            release(listenerList[i].dataLock)
            listenerListCount =  listenerListCount + 1
            release(listenerListLock)
            return i
    
    release(listenerListLock)
    return -1

proc delListenPort*(id: int) =
    #
    acquire(listenerListLock)
    
    if listenerListCount < 1 :
        release(listenerListLock)
        #echo "del error 1,ListCount= ",listenerListCount
        return # error no listener for id

    if listenerList[id].port == 0 :        
        release(listenerListLock)
        #echo "del error 2, Port= ", listenerList[id].port
        return # error no listener for id
    
    acquire(listenerList[id].dataLock)
    #echo "send closing data"
    sendEmpty(listenerList[id].port,listenerList[id].readSize)
    listenerList[id].run = false
    listenerList[id].port = 0
    listenerList[id].readSize = 0
    listenerList[id].data = nil
    listenerList[id].needRead = false
    release(listenerList[id].dataLock)
    deinitLock(listenerList[id].dataLock)
    listenerListCount = listenerListCount - 1

    release(listenerListLock)

proc recvData*(id: int,dataPtr : pointer) : int =  #returns size of the data recieved, -1 on error.
    if dataPtr == nil or id < 0 or id > MaxListen-1 :
        return -1

    
    if listenerList[id].port == 0 :        
        return -1 # error no listener for id
    
    acquire(listenerList[id].dataLock)
    if listenerList[id].needRead :
        var rTmp = listenerList[id].dataSize
        copyMem(dataPtr,listenerList[id].data,listenerList[id].dataSize) # dist , src , readSize
        listenerList[id].needRead = false
        release(listenerList[id].dataLock)
        return rTmp

    else:
        release(listenerList[id].dataLock)
        return -1





#------------Private Functions ------------------------

proc listenThread(listener:ptr ListenObj){.thread.} =
    
    sleep(NewThreadTimeOut)
    acquire(listener.dataLock) # acquire lock to read 'readSize'
    var rSize : int = listener.readSize
    if listener.port == 0 : # if destroyed before thread runs
        release(listener.dataLock)
        return

    release(listener.dataLock)
    
    var tmp : int = 0   
    var readBuf : pointer = allocShared0(sizeof(char)*listener.readSize)
    var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, false)
    
    acquire(listener.dataLock)
    #echo "listenThread port= ",listener.port
    socket.bindAddr(Port(listener.port))
    listener.data = readBuf
    listener.needRead = false
    
    while listener.run :
        
        while listener.needRead :  # Loop until recvData() makes the read and copy
            release(listener.dataLock)
            sleep(readWaitTime)
            acquire(listener.dataLock)
        
        release(listener.dataLock)  # Release while waiting for data
        tmp  = recv(socket,readBuf,rSize)
        #echo "Made a read with the size of ", tmp
        acquire(listener.dataLock)  # no bug! Testing shows if other thread deinintlock, acquire doesnt throw error.
        
        listener.dataSize = tmp
        listener.needRead = true    # recvData doesnt read buffer until set to true
                
           
    
    
    #acquire(listener.dataLock)
    deallocShared(readBuf)
    close(socket)
    #echo "Close Socket"
    release(listener.dataLock)

proc sendEmpty(port:int,size:int) =
    var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    var tmp : string = "                                   "
    for i in 0..size :
        socket.sendTo(LocalIp,Port(port),addr tmp,sizeof(string))
    close(socket)
    sleep(3)  

proc portIsOpen(port: int ): bool = #returns true if port is in use and false if not.
    
    var socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP) # create a UDP socket
    try:
        socket.bindAddr(Port(port)) #Tries to bind to specific port. If unable to bind to port. The port must be open or unavailable.
    except:
        return true # True port is open/unavailable
    
        #
    socket.close()
    return false
        
#------------------- Clean Up -------------------------


#



