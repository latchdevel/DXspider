/**
 * Ian's attempt at writing a socket module for the Spider GUI.
 * @author Ian Norton
 * @version 1.00 - 20010418.
 *
 * Copyright (C) 2001 Ian Norton.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public Licence as published by
 * the Free Software Foundation; either version 2 of the Licence, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public Licence for more details.
 *
 * You should have received a copy of the GNU General Public Licence
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Contacting the author :
 * Ian Norton
 * i.norton@lancaster.ac.uk
 * http://www.lancs.ac.uk/~norton/
 **/

import java.io.* ;
import java.net.* ;

public class Connection
    {
    // Host information.
    private String host ;
    private int port ;

    // Socket.
    private Socket socket ;
    
    // Socket input and output streams.
    private InputStream is ;
    private OutputStream os ;
    
    // Piped IO back up the chain.
    private PipedInputStream pin ;
    private PipedOutputStream pos ;

    // IO readers.
    private ConnectionInput conin ;
    private ConnectionOutput conout ;

    // Encoding String.
    public static final String encoding = "latin1"; // "ISO8859_1";   

    // Connection status.
    private boolean disconnected ;

    // Default port to use if one isn't specified.
    // private static final int DEFAULTPORT = 8000 ; // Use this for user client
    private static final int DEFAULTPORT = 27754 ;

    /**
     * Connection
     * @param PipedInputStream - Stream to read from
     * @param PipedOutputStream - Stream to send data to
     * @param Console - Where to send status alerts to.
     **/
    public Connection(PipedInputStream i, PipedOutputStream o, Console c)
        {
        // Initialise the IO pipes.
        pin = i ;
        pos = o ;

        // Yep, we're definately disconnected.
        disconnected = false ;

        // Initialise the Input and Output readers.
        conin = new ConnectionInput(pos, this) ;
        conout = new ConnectionOutput(pin, this) ;
        }

    /**
     * connect
     * @param String - host to connect to.  Port after a ':'.
     **/
    public void connect(String s)
        {
        // Has the socket been initialised?
        if(socket != null)
            disconnect() ;
        
        // Work out the hostname and port.
        if(s.indexOf(":") > - 1)
            {
            try
                {
                port = Integer.valueOf(s.substring(s.indexOf(":") + 1, s.length())).intValue() ;
                }
            catch(NumberFormatException ex)
                {
                System.out.println("Number format exception - bad int in String.") ;
                }

            s = s.substring(0, s.indexOf(":")) ;
            }
        else
            {
            port = DEFAULTPORT ;
            }

        host = s ;

        // Try and make the connection.
        try
            {
            socket = new Socket(host, port) ;
            }
        catch(UnknownHostException ex)
            {
            System.out.println("Connection: UnknownHostException") ;
            System.out.println(ex) ;
            }
        catch(IOException ex)
            {
            System.out.println("Connection: IOException") ;
            System.out.println(ex) ;
            }

        // Get the streams from the connection.
        try
            {
            is = socket.getInputStream() ;
            os = socket.getOutputStream() ;
            }
        catch(IOException ex)
            {
            System.out.println("Connection: IOException getting the connection streams") ;
            System.out.println(ex) ;
            }

        // Start the readers.
        conin.start(is) ;
        conout.start(os) ;

        // Write a "Connected to " message to the multiplexor.
        try
            {
            // Write disconnected to the PipedOutputStream.
            String output = "\nConnected to " + host + ":" + port + "\n" ;
            for(int i=0;i<output.length();i++)
                {
                pos.write(output.charAt(i)) ;
                }
            }
        catch(IOException ex)
            {

            }
            
        disconnected = false ;
        }

    /**
     * disconnect - disconnect the current connection.
     **/
    public void disconnect()
        {
        try
            {
            if(!disconnected)
                {
                disconnected = true ;
                conin.disconnect() ;
                conout.disconnect() ;

                // Write disconnected to the PipedOutputStream.
                String output = "\nDisconnected from " + host + ":" + port + "\n" ;
                for(int i=0;i<output.length();i++)
                    {
                    pos.write(output.charAt(i)) ;
                    }
                }


            if(socket != null) socket.close() ;
            }
        catch(IOException ex)
            {
            System.out.println("Connection: IOException closing socket") ;
            System.out.println(ex) ;
            }
        }
    } // End of class
