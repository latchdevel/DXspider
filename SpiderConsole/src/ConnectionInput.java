/**
 * ConnectionInput - reads from the socket and writes data to the pipe.
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

class ConnectionInput implements Runnable
    {
    // Debug me bugs
    public static final boolean DEBUG = false ;
    
    // Data streams.
    private InputStream is ;
    private PipedOutputStream pos ;

    // Connection object that created us.
    private Connection connection ;

    // Connection status.
    private boolean disconnected ;
    
    // Thread to run the read code in.
    private Thread t ;

    // Encoding string.
    public static final String encoding = "latin1"; // "ISO8859_1";   

    /**
     * ConnectionInput
     * @param InputStream - InputStream from the socket to read from
     * @param PipedOutputStream - Write the data out to here
     * @param Connection - the object that created us
     **/
    public ConnectionInput(PipedOutputStream p, Connection c)
        {
        // Initialise the streams & connection
        pos = p ;
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
            if(DEBUG) System.out.println("ConnectionInput: disconnect()") ;

            try { pos.flush() ; }
            catch(IOException ex) { }

            disconnected = true ;
            connection.disconnect() ;
            }
        }

    /**
     * start - begin reading.  Called when a connect has been achieved.
     **/
    public void start(InputStream i)
        {
        is = i ;

        disconnected = false ;

        // Initialise the thread to read data & start it.
        t = new Thread(this, "ConnectionInput") ;
        t.start() ;
        }

    /**
     * Thread run method.
     **/
    public void run()
        {
        byte[] b = new byte[16];   

        // Loop reading data.
        while(!disconnected)
            {
            try
                {
                // Read from InputStream and write to PipedOutputStream
                int n = 0;

                n = is.read(b) ;
                if(n > 0)
                    {
                    String output = new String(b, 0, n, encoding) ;
                    send(output) ;
                    }                                                   
                else if(n == -1)
                    {
                    this.disconnect() ;
                    }
                }
            catch(IOException ex)
                {
                if(disconnected)
                    return ;

                System.out.println("ConnectionInput: IOException reading data.") ;
                this.disconnect() ;
                }
            } // End while(true)
        } // End run()

    /**
     * send
     * @param String s - string to send to destination stream.
     **/
    private void send(String s)
        {
        try
            {
            // Write the data to the stream.
            for(int i=0;i<s.length();i++)
                {
                pos.write(s.charAt(i)) ;
                pos.flush() ;
                }
            }
        catch(IOException ex)
            {
            System.out.println("ConnectionInput:  IOException writing to multiplexor.") ;
            System.exit(1) ;
            }
        } // End of send(String s)
    } // End class

