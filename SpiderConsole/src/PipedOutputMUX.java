/**
 * OutputStreamMultiplexor 
 * Takes one output stream and sends it to multiple output streams.
 * @author Ian Norton
 * @version 1.0 - 20010418.
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

class PipedOutputMUX implements Runnable
    {
    public static final boolean DEBUG = false ;
    public static final String encoding = "latin1"; // "ISO8859_1";
    
    private PipedInputStream pin ;
    private Vector streams ;

    private Thread t ;
    
    /**
     * PipedOutputMUX initialiser
     * @param PipedOutputStream i - Source stream
     **/
    public PipedOutputMUX(PipedInputStream i)
        {
        pin = i ;
         
        // Streams Vector holds all the OutputStreams we know about.
        streams = new Vector() ;

        // Initialise and start the thread.
        t = new Thread(this, "OutputMultiplexor") ;
        t.start() ;
        }

    /**
     * addOutputStream
     * @param PipedOutputStream po - add a stream to send output to.
     **/
    public void addOutputStream(PipedOutputStream po)
        {
        // Add the supplied stream to the vector of streams.
        streams.addElement(po) ;
        }

    /**
     * run - Thread run method.
     **/
    public void run()
        {
        // Loop continually reading the input stream.
        while(true)
            {
            try
                {
                byte[] b = new byte[16];

                // Read a line and see if it has any data in it.
                int n = 0;

                // Trying to read
                while(pin.available() > 0)
                    {
                    int rdb = pin.available() ;
                    if(rdb > 16) rdb = 16 ;
                    n = pin.read(b, 0, rdb);

                    if(n > 0)
                        {
                        // Convert the output to a string and send it.
                        String output = new String(b, 0, n, encoding) ;
                        if(DEBUG) System.out.println(output) ;
                        send(output) ;
                        }
                    }
                }
            catch(IOException ex)
                {
                System.out.println("PipedOutputMUX: IOException trying to read.") ;
                System.exit(1) ;
                }
            } // End of loop
        } // End of run()

    /**
     * send
     * @param String s - string to send to all streams.
     **/
    private void send(String s)
        {
        // Calendar cal = Calendar.getInstance() ;
        // if(DEBUG) System.out.println("PipedOutputMUX: " + cal.getTime() + " Send called with :" + s) ;

        // If we have no streams, then we can't do anything.
        if(streams.size() == 0) return ;
        
        // Create Enumeration object to enumerate with :-)
        Enumeration e = streams.elements() ;

        // Go through the enumeration and send the string to each stream.
        while(e.hasMoreElements())
            {
            PipedOutputStream os = (PipedOutputStream)e.nextElement() ;

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
                // If we get an IO exception, then the other end of the pipe
                // has been closed.  We need to remove this stream.
                streams.removeElement(os) ;
                System.out.println("IOException - stream removed.") ;
                }
            }
        }

    } // End of class.
