/**
 * Command Buffer for the cluster window of the spider GUI.
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
 * http://www.lancs.ac.uk/~norton/                                               **/

import java.util.Vector ;

class CommandBuffer
    {
    private int top, bottom, pointer, size ;
    private Vector buffer ;
    private boolean rolled ;

    /**
     * main - testing purposes only.
     **/
    public static void main(String[] args)
        {
        CommandBuffer c = new CommandBuffer(5) ;
        c.addCommand("1") ;
        System.out.println(c.getPreviousCommand()) ;
        System.out.println(c.getNextCommand()) ;
        }

    /**
     * CommandBuffer
     * @param int - Number of lines of buffer.
     **/
     public CommandBuffer(int i)
        {
        // Size of the buffer.
        size = i ;

        // "Pointers"
        bottom = 0 ;
        pointer = 0 ;

        top = size - 1 ;

        // Vector that does that actual storage.
        buffer = new Vector(size) ;
        }

    /**
     * addCommand
     * @param String - command to add to the buffer
     **/
    public void addCommand(String s)
        {
        // Is it an empty string
        if(s.length() == 0) return ;
        
        // Add the command to the buffer
        buffer.addElement(s) ;

        // Check the buffer remains the correct size.
        while(buffer.size() > size) buffer.removeElementAt(0) ;
        
        // Pointer to the last command
        pointer = buffer.indexOf(s) ;
        }

    /**
     * getPreviousCommand - get the previous command (recursive)
     * @returns String - previous command
     **/
    public String getPreviousCommand()
        {
        String output = (String)buffer.elementAt(pointer) ;
        if(pointer != 0) pointer-- ;
        return output ;
        }

    /**
     * getNextCommand - get the next command (recursive)
     * @returns String - next command
     **/
    public String getNextCommand()
        {
        pointer++ ;
        if(pointer == buffer.size())
            {
            pointer-- ;
            return "" ;
            }
        String output = (String)buffer.elementAt(pointer) ;
        return output ;
        }
    } // End of class.
