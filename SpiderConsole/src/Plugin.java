/**
 * Plugin - abstract plugin class.
 * We need this so that when we compile Console, it knows what methods to
 * expect in plugin modules.  If we don't use this it will complain.
 * Any methods added to plugins need to be added to ALL plugins and here.
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

import javax.swing.*;
import java.io.PipedInputStream ;
import java.io.PipedOutputStream ;

public abstract class Plugin extends JPanel{
    public abstract void init(PipedInputStream i, PipedOutputStream o) ;
    public abstract String getTabName() ;
    public abstract String getTabTip() ;
    }
