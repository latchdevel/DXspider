/**
 * LimitedStyledDocument
 * @author Ian Norton
 * @version 1.0 20010418.
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

import java.awt.* ;
import javax.swing.*; 
import javax.swing.text.*; 
import java.awt.Toolkit;
import java.util.* ;

public class LimitedStyledDocument extends DefaultStyledDocument 
    {
    int scrollbufferlines ;
    SimpleAttributeSet attr ;
    int num ;

    public LimitedStyledDocument(int i) 
        {
        scrollbufferlines = i ;
        attr = new SimpleAttributeSet() ;
        num = 0 ;
        }

    /**
     * append - append a string to the end of the document keeping the
     *          number of lines in the document at or below maxscrollbuffer.
     * @param String s - String to append.
     * @param AttributeSet a - Attributes of the string to append.
     **/
    public void append(String s, AttributeSet a)
        {
        // Try and append the string to the document.
        try
            {
            super.insertString(super.getLength(), s, a) ;
            }
        catch(BadLocationException ex)
            {
            }

        StringTokenizer st = null ;

        // Split the document into tokens delimited by '\n'.
        try
            {
            // Need to do clever stuff here to chop the top off the buffer.
            st = new StringTokenizer(super.getText(0, super.getLength()), "\n") ;
            }
        catch(BadLocationException ex)
            {
            }
 
        int i = 0;

        // Are there more lines than there should be?
        if(st.countTokens() > scrollbufferlines)
            {
            // How many lines too many?
            i = st.countTokens() - scrollbufferlines ;
            }
 
        // For each line too many
        for(;i>0;i--)
            {
            String tmp = st.nextToken() ;

            try
                {
                // Remove the line.
                super.remove(0, super.getText(0, super.getLength()).indexOf(tmp) + tmp.length()) ;
                }
            catch(BadLocationException ex)
                {
                }
            } // End of for(;i>0;i--)
        } // End of append
    } // End of class.
