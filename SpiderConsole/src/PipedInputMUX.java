/**
 * InputStreamMultiplexor 
 * This takes multiple input streams and sends them to one input stream.
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
import java.util.Vector ;
import java.util.Enumeration ;
import java.util.Calendar ;

class PipedInputMUX implements Runnable
    {
    public static final boolean DEBUG = false ;
    public static final String encoding = "latin1"; // "ISO8859_1";

    private PipedOutputStream pos ;
    private Vector streams ;

    private Thread t ;
    
    /**
     * PipedInputMUX initialiser.
     * @param PipedOutputStream - target stream.
     **/
    public PipedInputMUX(PipedOutputStream o)
        {
        pos = o ;

        // Streams Vector holds all the InputStreams we know about.
        streams = new Vector() ;

        // Initialise and start the thread.
        t = new Thread(this, "InputMultiplexor") ;
        t.start() ;
        }

    /**
     * addInputStream
     * @param PipedInputStream pi - add a stream get input from.
     **/
    public void addInputStream(PipedInputStream pi)
        {
        // Add the supplied stream to the vector of streams.
        streams.addElement(pi) ;
        }

    /**
     * run - Thread run method.
     **/
    public void run()
        {
        // Loop continually reading from the input streams
        while(true)
            {
            // Enumeration thing here.
            Enumeration e = streams.elements() ;
 
            byte[] b = new byte[16];

            while(e.hasMoreElements())
                {
                PipedInputStream is = (PipedInputStream)e.nextElement() ;
                
                try
                    {
                    // Read a line and see if it has any data in it.
                    int n = 0;

                    // While there is non-blocking data available to read
                    while(is.available() > 0)
                        {
                        // find out how many bytes we can read without blocking
                        int rdb = is.available() ;
                        if(rdb > 16) rdb = 16 ;
                        
                        // Read that many bytes and return.
                        n = is.read(b, 0, rdb);
                        if(n > 0)
                            {
                            String output = new String(b, 0, n, encoding) ;
                            send(output) ;
                            }
                        }
     
                    if(DEBUG) System.out.println("After reading a line.") ;
                    }
                catch(IOException ex)
                    {
                    // If we get an IO exception, then the other end of the pipe
                    // has been closed.  We need to remove this stream.
                    streams.removeElement(is) ;
                    System.out.println("IOException - stream removed.") ;
                    }
                                                                                
                } // End of while(e.hasMoreElements())
            } // End of while(true)
        } // End of run()

    /**
     * send
     * @param String s - string to send to destination stream.
     **/
    private void send(String s)
        {
        // Calendar cal = Calendar.getInstance() ;
        // if(DEBUG) System.out.println("PipedInputMUX: " + cal.getTime() + " Send called with : " + s) ;

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
            System.out.println("PipedInputMUX: IOException on destination stream.") ;
            }
        }
    } // End of class.
