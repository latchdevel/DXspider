/**
 * ConnectionOutput - reads from the pipe and writes data to the socket.
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

class ConnectionOutput implements Runnable
    {
    // Debug me bugs
    public static final boolean DEBUG = false ;
    
    // Data streams.
    private OutputStream os ;
    private PipedInputStream pin ;

    // Connection object that created us.
    private Connection connection ;

    // Connection status.
    private boolean disconnected ;
    
    // Thread to run the read code in.
    private Thread t ;

    // Encoding string.
    public static final String encoding = "latin1"; // "ISO8859_1";   

    /**
     * ConnectionOutput
     * @param OutputStream - OutputStream to the socket to write to
     * @param PipedInputStream - Read data from here
     * @param Connection - the object that created us                           
     **/
    public ConnectionOutput(PipedInputStream p, Connection c)
        {
        // Initialise the streams & connection
        pin = p ;
        connection = c ;

        disconnected = true ;
        }

    /**
     * disconnect - disconnect the current connection.
     **/                                                                        
    public void disconnect()
        {
        if(!disconnected)
            {
            if(DEBUG) System.out.println("ConnectionOutput: disconnect()") ;

            disconnected = true ;
            connection.disconnect() ;
            }
        }

    /**
     * start - begin reading.  Called when a connect has been achieved.
     **/
    public void start(OutputStream o)
        {
        os = o ;

        disconnected = false ;

        // Test to see if the thread has been inititialised.
        if(t == null) ;
            {
            if(DEBUG) System.out.println("ConnectionOutput: Creating thread.") ;

            // Initialise the thread to read data & start it.
            t = new Thread(this, "Connection") ;
            t.start() ;
            }
        }

    /**
     * Thread run method.
     **/
    public void run()
        {
        byte[] b = new byte[16];

        // Loop reading data.
        while(true)
            {
            try
                {
                // Read from PipedInputStream and write to OutputStream
                int n = 0;

                // Read that many bytes and return.
                n = pin.read(b);

                // If disconnected read and disguard data or the MUX dies.
                if(n > 0 && !disconnected)
                    {
                    String output = new String(b, 0, n, encoding) ;
                    send(output) ;
                    }                                                   
                }
            catch(IOException ex)
                {
                System.out.println("ConnectionOutput: IOException reading data from multiplexor.") ;
                System.exit(1) ;
                }
            } // End while(true)
        } // End run()

    /**
     * send
     * @param String s - string to send to destination stream.
     **/
    private void send(String s)
        {
        if(DEBUG) System.out.println("ConnectionOutput: Send called : " + s) ;
        try
            {
            // Write the data to the stream.
            for(int i=0;i<s.length();i++)
                {
                os.write(s.charAt(i)) ;
                os.flush() ;
                }
            }
        catch(IOException ex)
            {
            System.out.println("ConnectionOutput:  IOException writing to socket.") ;
            System.exit(1) ;
            }                                                                   
        }
    } // End class

